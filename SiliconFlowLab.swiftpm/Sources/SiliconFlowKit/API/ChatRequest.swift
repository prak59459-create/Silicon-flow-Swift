import Foundation

public enum ChatRole: String, Codable, Sendable, Hashable {
    case system
    case user
    case assistant
}

/// 画像の解像度ヒント
public enum ImageDetail: String, Codable, Sendable, Hashable {
    case auto
    case low
    case high
}

/// マルチモーダル入力の 1 パーツ
public enum ChatContentPart: Encodable, Sendable, Hashable {
    case text(String)
    /// URL または `data:image/jpeg;base64,...`
    case imageURL(String, detail: ImageDetail?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    enum ImageKeys: String, CodingKey {
        case url
        case detail
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url, let detail):
            try container.encode("image_url", forKey: .type)
            var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
            try image.encode(url, forKey: .url)
            try image.encodeIfPresent(detail, forKey: .detail)
        }
    }
}

/// メッセージ本文（文字列 or パーツ配列）
public enum ChatContent: Encodable, Sendable, Hashable {
    case text(String)
    case parts([ChatContentPart])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

/// 送信するメッセージ
public struct ChatMessagePayload: Encodable, Sendable, Hashable {
    public var role: ChatRole
    public var content: ChatContent

    public init(role: ChatRole, content: ChatContent) {
        self.role = role
        self.content = content
    }

    public init(role: ChatRole, text: String) {
        self.init(role: role, content: .text(text))
    }
}

/// `POST /chat/completions` のリクエスト。nil の項目は送信しません。
public struct ChatCompletionRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var messages: [ChatMessagePayload]
    public var stream: Bool
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var frequencyPenalty: Double?
    public var enableThinking: Bool?
    public var thinkingBudget: Int?
    public var stop: [String]?
    public var jsonMode: Bool

    public init(
        model: String,
        messages: [ChatMessagePayload],
        stream: Bool = true,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        frequencyPenalty: Double? = nil,
        enableThinking: Bool? = nil,
        thinkingBudget: Int? = nil,
        stop: [String]? = nil,
        jsonMode: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.enableThinking = enableThinking
        self.thinkingBudget = thinkingBudget
        self.stop = stop
        self.jsonMode = jsonMode
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case frequencyPenalty = "frequency_penalty"
        case enableThinking = "enable_thinking"
        case thinkingBudget = "thinking_budget"
        case stop
        case responseFormat = "response_format"
    }

    enum ResponseFormatKeys: String, CodingKey {
        case type
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
        try container.encodeIfPresent(enableThinking, forKey: .enableThinking)
        try container.encodeIfPresent(thinkingBudget, forKey: .thinkingBudget)
        if let stop, !stop.isEmpty {
            try container.encode(Array(stop.prefix(4)), forKey: .stop)
        }
        if jsonMode {
            var format = container.nestedContainer(keyedBy: ResponseFormatKeys.self, forKey: .responseFormat)
            try format.encode("json_object", forKey: .type)
        }
    }
}
