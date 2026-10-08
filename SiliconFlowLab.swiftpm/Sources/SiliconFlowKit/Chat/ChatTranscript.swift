import Foundation

/// 会話の 1 メッセージ（画面表示・保存用）
public struct ChatTurn: Identifiable, Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case complete
        case streaming
        case failed
        case cancelled
    }

    public var id: UUID
    public var role: ChatRole
    public var content: String
    public var reasoning: String
    /// 添付画像（data URL）。保存時のサイズを抑えるため縮小済みのものだけを入れます。
    public var imageDataURLs: [String]
    public var createdAt: Date
    public var state: State
    public var usage: Usage?
    /// usage が API から返らず、文字数から見積もった値か
    public var usageIsEstimated: Bool?
    public var metrics: GenerationMetrics?
    public var finishReason: String?
    public var cost: Money?
    public var model: String?
    public var errorTitle: String?

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoning: String = "",
        imageDataURLs: [String] = [],
        createdAt: Date = Date(),
        state: State = .complete
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.imageDataURLs = imageDataURLs
        self.createdAt = createdAt
        self.state = state
    }

    /// API に送る形に変換します。失敗・空のメッセージは送りません。
    public var payload: ChatMessagePayload? {
        guard state != .failed else { return nil }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageDataURLs.isEmpty {
            guard !text.isEmpty else { return nil }
            return ChatMessagePayload(role: role, text: content)
        }
        var parts: [ChatContentPart] = imageDataURLs.map { .imageURL($0, detail: .auto) }
        if !text.isEmpty { parts.append(.text(content)) }
        return ChatMessagePayload(role: role, content: .parts(parts))
    }
}

public enum ChatTranscript {
    /// 会話履歴から送信用メッセージを作ります（思考内容は送りません＝公式の推奨どおり）。
    public static func payloads(from turns: [ChatTurn]) -> [ChatMessagePayload] {
        turns.compactMap(\.payload)
    }

    /// Markdown 形式で書き出します（共有用）。
    public static func markdown(turns: [ChatTurn], model: String) -> String {
        var lines = ["# \(model) との会話", ""]
        for turn in turns where turn.state != .failed {
            let speaker: String
            switch turn.role {
            case .user: speaker = "**あなた**"
            case .assistant: speaker = "**\(ModelClassifier.shortName(of: turn.model ?? model))**"
            case .system: speaker = "**システム**"
            }
            lines.append(speaker)
            if !turn.imageDataURLs.isEmpty { lines.append("（画像 \(turn.imageDataURLs.count) 枚を添付）") }
            lines.append(turn.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
