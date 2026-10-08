import Foundation
import SiliconFlowKit

/// 1 つのモデルとの会話
@MainActor
final class ChatSession: ObservableObject {
    let modelID: String

    @Published private(set) var turns: [ChatTurn] = []
    @Published var draft = ""
    /// 送信前の添付画像（data URL）
    @Published var attachments: [String] = []
    @Published private(set) var isGenerating = false
    /// 生成中の回答（画面の更新回数を抑えるため間引いて反映）
    @Published private(set) var liveContent = ""
    @Published private(set) var liveReasoning = ""
    @Published private(set) var lastError: SiliconFlowError?

    private var task: Task<Void, Never>?
    private var streamingTurnID: UUID?

    /// 画面更新の最小間隔（秒）。トークンごとに再描画すると重くなるため。
    private let flushInterval: TimeInterval = 0.06

    init(modelID: String) {
        self.modelID = modelID
    }

    var canSend: Bool {
        !isGenerating && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    var hasConversation: Bool { !turns.isEmpty }

    // MARK: - 操作

    func send(settings: AppSettings, entry: CatalogEntry?) {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        turns.append(ChatTurn(role: .user, content: text, imageDataURLs: attachments))
        draft = ""
        attachments = []
        generate(settings: settings, entry: entry)
    }

    /// 最後の回答を消して送り直します（失敗時の再試行・作り直し）。
    func retry(settings: AppSettings, entry: CatalogEntry?) {
        guard !isGenerating else { return }
        if let last = turns.last, last.role == .assistant { turns.removeLast() }
        guard turns.last?.role == .user else { return }
        generate(settings: settings, entry: entry)
    }

    func stop() {
        task?.cancel()
    }

    func clear() {
        stop()
        turns.removeAll()
        lastError = nil
        liveContent = ""
        liveReasoning = ""
    }

    func dismissError() {
        lastError = nil
    }

    func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
    }

    // MARK: - 生成

    private func generate(settings: AppSettings, entry: CatalogEntry?) {
        let client = settings.makeClient()
        let parameters = settings.chatParameters
        let request = parameters.makeRequest(model: modelID, history: ChatTranscript.payloads(from: turns))
        var placeholder = ChatTurn(role: .assistant, content: "", state: .streaming)
        placeholder.model = modelID
        turns.append(placeholder)
        streamingTurnID = placeholder.id
        isGenerating = true
        lastError = nil
        liveContent = ""
        liveReasoning = ""
        let promptEstimate = request.messages.reduce(0) { total, message in
            if case .text(let text) = message.content { return total + TokenEstimator.estimate(text) }
            return total + 800
        }
        task = Task { [weak self] in
            await self?.run(request: request, client: client, streaming: parameters.useStreaming, entry: entry, promptEstimate: promptEstimate)
        }
    }

    private func run(request: ChatCompletionRequest, client: SiliconFlowClient, streaming: Bool, entry: CatalogEntry?, promptEstimate: Int) async {
        var accumulator = GenerationAccumulator(startedAt: Self.now())
        var lastFlush: TimeInterval = 0
        do {
            if streaming {
                for try await chunk in client.streamChat(request) {
                    let now = Self.now()
                    if accumulator.apply(chunk, at: now), now - lastFlush >= flushInterval {
                        liveContent = accumulator.content
                        liveReasoning = accumulator.reasoning
                        lastFlush = now
                    }
                }
                if Task.isCancelled { throw CancellationError() }
            } else {
                let response = try await client.chat(request)
                accumulator.apply(response, at: Self.now())
            }
            accumulator.finish(at: Self.now())
            finish(accumulator, state: .complete, entry: entry, promptEstimate: promptEstimate)
            if accumulator.content.isEmpty, accumulator.reasoning.isEmpty {
                lastError = SiliconFlowError(kind: .emptyResponse, endpoint: "POST /chat/completions", region: client.region, modelID: modelID)
            }
        } catch {
            accumulator.finish(at: Self.now())
            let wrapped = SiliconFlowError.wrap(error, endpoint: "POST /chat/completions", region: client.region, modelID: modelID)
            let hasOutput = !accumulator.content.isEmpty || !accumulator.reasoning.isEmpty
            if wrapped.isCancellation {
                finish(accumulator, state: hasOutput ? .cancelled : .failed, entry: entry, promptEstimate: promptEstimate)
                if !hasOutput, let last = turns.last, last.role == .assistant { turns.removeLast() }
            } else {
                finish(accumulator, state: hasOutput ? .complete : .failed, entry: entry, promptEstimate: promptEstimate, errorTitle: wrapped.diagnosis.title)
                lastError = wrapped
            }
        }
        isGenerating = false
        liveContent = ""
        liveReasoning = ""
        streamingTurnID = nil
        task = nil
    }

    private func finish(_ accumulator: GenerationAccumulator, state: ChatTurn.State, entry: CatalogEntry?, promptEstimate: Int, errorTitle: String? = nil) {
        guard let id = streamingTurnID, let index = turns.firstIndex(where: { $0.id == id }) else { return }
        var turn = turns[index]
        turn.content = accumulator.content
        turn.reasoning = accumulator.reasoning
        turn.state = state
        turn.metrics = accumulator.metrics
        turn.finishReason = accumulator.finishReason
        turn.model = accumulator.model ?? modelID
        turn.errorTitle = errorTitle
        if let usage = accumulator.usage {
            turn.usage = usage
            turn.usageIsEstimated = false
        } else if state != .failed {
            turn.usage = Usage(promptTokens: promptEstimate, completionTokens: accumulator.completionTokensEstimate)
            turn.usageIsEstimated = true
        }
        turn.cost = CostEstimator.cost(usage: turn.usage, entry: entry)
        turns[index] = turn
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// モデルごとの会話を保持します（モデルを切り替えても会話が残るように）。
@MainActor
final class ChatSessionRegistry: ObservableObject {
    private var sessions: [String: ChatSession] = [:]

    func session(for modelID: String) -> ChatSession {
        if let existing = sessions[modelID] { return existing }
        let session = ChatSession(modelID: modelID)
        sessions[modelID] = session
        return session
    }

    func clearAll() {
        for session in sessions.values { session.clear() }
        sessions.removeAll()
    }
}
