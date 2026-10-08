import Foundation

/// トークン使用量
public struct Usage: Codable, Sendable, Hashable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    /// 出力のうち思考（推論）に使ったトークン
    public var reasoningTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil, reasoningTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case completionTokensDetails = "completion_tokens_details"
        case reasoningTokens = "reasoning_tokens"
    }

    enum DetailKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try? container.decodeIfPresent(Int.self, forKey: .promptTokens)
        completionTokens = try? container.decodeIfPresent(Int.self, forKey: .completionTokens)
        totalTokens = try? container.decodeIfPresent(Int.self, forKey: .totalTokens)
        var reasoning = try? container.decodeIfPresent(Int.self, forKey: .reasoningTokens)
        if reasoning == nil, let details = try? container.nestedContainer(keyedBy: DetailKeys.self, forKey: .completionTokensDetails) {
            reasoning = try? details.decodeIfPresent(Int.self, forKey: .reasoningTokens)
        }
        reasoningTokens = reasoning
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
        try container.encodeIfPresent(reasoningTokens, forKey: .reasoningTokens)
    }

    /// 合計（無ければ入力 + 出力）
    public var effectiveTotal: Int? {
        if let totalTokens { return totalTokens }
        guard let promptTokens, let completionTokens else { return nil }
        return promptTokens + completionTokens
    }
}

/// 回答メッセージ（通常応答）または差分（ストリーミング）
public struct ChatMessageDelta: Decodable, Sendable, Hashable {
    public var role: String?
    public var content: String?
    public var reasoningContent: String?

    public init(role: String? = nil, content: String? = nil, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case reasoning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        content = try? container.decodeIfPresent(String.self, forKey: .content)
        reasoningContent = (try? container.decodeIfPresent(String.self, forKey: .reasoningContent))
            ?? (try? container.decodeIfPresent(String.self, forKey: .reasoning))
    }
}

public struct ChatChoice: Decodable, Sendable, Hashable {
    public var index: Int?
    /// 通常応答
    public var message: ChatMessageDelta?
    /// ストリーミングの差分
    public var delta: ChatMessageDelta?
    public var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case delta
        case finishReason = "finish_reason"
    }

    public init(index: Int? = 0, message: ChatMessageDelta? = nil, delta: ChatMessageDelta? = nil, finishReason: String? = nil) {
        self.index = index
        self.message = message
        self.delta = delta
        self.finishReason = finishReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try? container.decodeIfPresent(Int.self, forKey: .index)
        message = try? container.decodeIfPresent(ChatMessageDelta.self, forKey: .message)
        delta = try? container.decodeIfPresent(ChatMessageDelta.self, forKey: .delta)
        finishReason = try? container.decodeIfPresent(String.self, forKey: .finishReason)
    }
}

/// `POST /chat/completions` のレスポンス（通常応答・ストリーミングの 1 チャンク兼用）
public struct ChatCompletionChunk: Decodable, Sendable, Hashable {
    public var id: String?
    public var model: String?
    public var choices: [ChatChoice]
    public var usage: Usage?

    public init(id: String? = nil, model: String? = nil, choices: [ChatChoice], usage: Usage? = nil) {
        self.id = id
        self.model = model
        self.choices = choices
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case choices
        case usage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        choices = (try? container.decodeIfPresent([ChatChoice].self, forKey: .choices)) ?? []
        usage = try? container.decodeIfPresent(Usage.self, forKey: .usage)
    }

    /// 最初の選択肢の本文（通常応答なら message、ストリームなら delta）
    public var primaryContent: String? {
        choices.first?.message?.content ?? choices.first?.delta?.content
    }

    public var primaryReasoning: String? {
        choices.first?.message?.reasoningContent ?? choices.first?.delta?.reasoningContent
    }

    public var finishReason: String? { choices.first?.finishReason }
}

/// 通常（非ストリーミング）応答も同じ型で扱います。
public typealias ChatCompletionResponse = ChatCompletionChunk
