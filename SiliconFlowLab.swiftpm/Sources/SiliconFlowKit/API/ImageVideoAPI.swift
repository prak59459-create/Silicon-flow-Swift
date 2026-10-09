import Foundation

/// `POST /images/generations` のリクエスト
public struct ImageGenerationRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var prompt: String
    public var negativePrompt: String?
    public var imageSize: String?
    public var batchSize: Int?
    public var seed: Int?
    public var numInferenceSteps: Int?
    public var guidanceScale: Double?
    /// 画像編集モデル用の元画像（URL または data URL）
    public var image: String?

    public init(
        model: String, prompt: String, negativePrompt: String? = nil, imageSize: String? = nil, batchSize: Int? = nil,
        seed: Int? = nil, numInferenceSteps: Int? = nil, guidanceScale: Double? = nil, image: String? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.imageSize = imageSize
        self.batchSize = batchSize
        self.seed = seed
        self.numInferenceSteps = numInferenceSteps
        self.guidanceScale = guidanceScale
        self.image = image
    }

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case negativePrompt = "negative_prompt"
        case imageSize = "image_size"
        case batchSize = "batch_size"
        case seed
        case numInferenceSteps = "num_inference_steps"
        case guidanceScale = "guidance_scale"
        case image
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        if let negativePrompt, !negativePrompt.isEmpty { try container.encode(negativePrompt, forKey: .negativePrompt) }
        try container.encodeIfPresent(imageSize, forKey: .imageSize)
        try container.encodeIfPresent(batchSize, forKey: .batchSize)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encodeIfPresent(numInferenceSteps, forKey: .numInferenceSteps)
        try container.encodeIfPresent(guidanceScale, forKey: .guidanceScale)
        try container.encodeIfPresent(image, forKey: .image)
    }

    /// よく使う画像サイズ（多くのモデルが対応）
    public static let commonSizes = ["1024x1024", "512x512", "768x1024", "1024x768", "576x1024", "1024x576", "1328x1328", "1664x928", "928x1664"]
}

/// `POST /images/generations` のレスポンス
public struct ImageGenerationResponse: Decodable, Sendable, Hashable {
    public struct GeneratedImage: Decodable, Sendable, Hashable {
        public var url: String?
        public var b64JSON: String?

        enum CodingKeys: String, CodingKey {
            case url
            case b64JSON = "b64_json"
        }
    }

    public struct Timings: Decodable, Sendable, Hashable {
        public var inference: Double?
    }

    public var images: [GeneratedImage]
    public var timings: Timings?
    public var seed: Int?

    enum CodingKeys: String, CodingKey {
        case images
        case data
        case timings
        case seed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primary = (try? container.decodeIfPresent([GeneratedImage].self, forKey: .images)) ?? nil
        let secondary = (try? container.decodeIfPresent([GeneratedImage].self, forKey: .data)) ?? nil
        images = primary ?? secondary ?? []
        timings = try? container.decodeIfPresent(Timings.self, forKey: .timings)
        seed = try? container.decodeIfPresent(Int.self, forKey: .seed)
    }

    public var imageURLs: [URL] { images.compactMap { $0.url.flatMap(URL.init(string:)) } }
}

/// `POST /video/submit` のリクエスト
public struct VideoSubmitRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var prompt: String
    public var negativePrompt: String?
    public var imageSize: String?
    public var image: String?
    public var seed: Int?

    public init(model: String, prompt: String, negativePrompt: String? = nil, imageSize: String? = nil, image: String? = nil, seed: Int? = nil) {
        self.model = model
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.imageSize = imageSize
        self.image = image
        self.seed = seed
    }

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case negativePrompt = "negative_prompt"
        case imageSize = "image_size"
        case image
        case seed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        if let negativePrompt, !negativePrompt.isEmpty { try container.encode(negativePrompt, forKey: .negativePrompt) }
        try container.encodeIfPresent(imageSize, forKey: .imageSize)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(seed, forKey: .seed)
    }

    public static let commonSizes = ["1280x720", "720x1280", "960x960"]
}

public struct VideoSubmitResponse: Decodable, Sendable, Hashable {
    public var requestID: String

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
    }
}

/// `POST /video/status` のレスポンス
public struct VideoStatusResponse: Decodable, Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case succeed = "Succeed"
        case inQueue = "InQueue"
        case inProgress = "InProgress"
        case failed = "Failed"
        case unknown

        public var label: String {
            switch self {
            case .succeed: return "完了"
            case .inQueue: return "順番待ち"
            case .inProgress: return "生成中"
            case .failed: return "失敗"
            case .unknown: return "不明"
            }
        }

        public var isFinished: Bool { self == .succeed || self == .failed }
    }

    public var status: Status
    public var reason: String?
    public var videoURLs: [URL]

    enum CodingKeys: String, CodingKey {
        case status
        case reason
        case results
    }

    struct Results: Decodable {
        struct Video: Decodable {
            var url: String?
        }

        var videos: [Video]?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        status = raw.flatMap(Status.init(rawValue:)) ?? .unknown
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        let results = (try? container.decodeIfPresent(Results.self, forKey: .results)) ?? nil
        videoURLs = (results?.videos ?? []).compactMap { $0.url.flatMap(URL.init(string:)) }
    }
}
