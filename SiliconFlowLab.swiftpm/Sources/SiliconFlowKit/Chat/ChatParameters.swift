import Foundation

/// チャットの生成パラメータ（画面の設定を保存する形）
public struct ChatParameters: Codable, Sendable, Equatable {
    public enum ThinkingMode: String, Codable, Sendable, CaseIterable, Identifiable {
        /// 送らない（モデルの既定に任せる）
        case automatic
        case on
        case off

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .automatic: return "自動（モデルの既定）"
            case .on: return "オン"
            case .off: return "オフ"
            }
        }
    }

    public var systemPrompt: String
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var useStreaming: Bool
    public var thinking: ThinkingMode
    public var thinkingBudget: Int
    public var jsonMode: Bool
    /// 送信する過去メッセージの上限（長くなりすぎるのを防ぐ）
    public var historyLimit: Int

    public init(
        systemPrompt: String = "",
        temperature: Double = 0.7,
        topP: Double = 0.7,
        maxTokens: Int = 2048,
        useStreaming: Bool = true,
        thinking: ThinkingMode = .automatic,
        thinkingBudget: Int = 4096,
        jsonMode: Bool = false,
        historyLimit: Int = 20
    ) {
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.useStreaming = useStreaming
        self.thinking = thinking
        self.thinkingBudget = thinkingBudget
        self.jsonMode = jsonMode
        self.historyLimit = historyLimit
    }

    public static let `default` = ChatParameters()

    /// 値を API が受け付ける範囲に収めます。
    public var clamped: ChatParameters {
        var copy = self
        copy.temperature = min(2, max(0, temperature))
        copy.topP = min(1, max(0.01, topP))
        copy.maxTokens = min(32768, max(1, maxTokens))
        copy.thinkingBudget = min(32768, max(128, thinkingBudget))
        copy.historyLimit = min(100, max(1, historyLimit))
        return copy
    }

    /// リクエストを組み立てます。
    public func makeRequest(model: String, history: [ChatMessagePayload]) -> ChatCompletionRequest {
        let parameters = clamped
        var messages: [ChatMessagePayload] = []
        let system = parameters.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty { messages.append(ChatMessagePayload(role: .system, text: system)) }
        // 古い履歴を切り捨てたとき、assistant から始まると受け付けないモデルがあるので user から始める
        var recent = Array(history.suffix(parameters.historyLimit))
        while recent.count > 1, recent.first?.role == .assistant { recent.removeFirst() }
        messages.append(contentsOf: recent)
        var enableThinking: Bool?
        var budget: Int?
        switch parameters.thinking {
        case .automatic: break
        case .on:
            enableThinking = true
            budget = parameters.thinkingBudget
        case .off:
            enableThinking = false
        }
        return ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: parameters.useStreaming,
            maxTokens: parameters.maxTokens,
            temperature: parameters.temperature,
            topP: parameters.topP,
            enableThinking: enableThinking,
            thinkingBudget: budget,
            jsonMode: parameters.jsonMode
        )
    }
}
