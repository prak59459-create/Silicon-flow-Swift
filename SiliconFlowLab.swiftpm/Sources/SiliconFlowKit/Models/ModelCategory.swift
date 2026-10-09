import Foundation

/// モデルの種類（どの「試す」画面を使うかを決めます）
public enum ModelCategory: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case chat
    case vision
    case embedding
    case reranker
    case textToImage
    case imageToImage
    case textToSpeech
    case speechToText
    case textToVideo
    case imageToVideo
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chat: return "チャット"
        case .vision: return "画像理解 (VLM)"
        case .embedding: return "埋め込み"
        case .reranker: return "リランク"
        case .textToImage: return "画像生成"
        case .imageToImage: return "画像編集"
        case .textToSpeech: return "音声合成"
        case .speechToText: return "音声認識"
        case .textToVideo: return "動画生成"
        case .imageToVideo: return "画像→動画"
        case .other: return "その他"
        }
    }

    public var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .vision: return "eye"
        case .embedding: return "circle.hexagongrid"
        case .reranker: return "list.number"
        case .textToImage: return "photo"
        case .imageToImage: return "wand.and.stars"
        case .textToSpeech: return "speaker.wave.2"
        case .speechToText: return "waveform"
        case .textToVideo: return "film"
        case .imageToVideo: return "play.rectangle"
        case .other: return "questionmark.circle"
        }
    }

    /// チャット画面で試せるか
    public var isChatLike: Bool { self == .chat || self == .vision }

    /// 公式 API の sub_type 値との対応
    public init?(apiSubType: String) {
        switch apiSubType.lowercased() {
        case "chat": self = .chat
        case "embedding": self = .embedding
        case "reranker", "rerank": self = .reranker
        case "text-to-image": self = .textToImage
        case "image-to-image": self = .imageToImage
        case "text-to-speech": self = .textToSpeech
        case "speech-to-text": self = .speechToText
        case "text-to-video": self = .textToVideo
        case "image-to-video": self = .imageToVideo
        default: return nil
        }
    }

    public var apiSubType: String? {
        switch self {
        case .chat, .vision: return "chat"
        case .embedding: return "embedding"
        case .reranker: return "reranker"
        case .textToImage: return "text-to-image"
        case .imageToImage: return "image-to-image"
        case .textToSpeech: return "text-to-speech"
        case .speechToText: return "speech-to-text"
        case .textToVideo: return "text-to-video"
        case .imageToVideo: return "image-to-video"
        case .other: return nil
        }
    }

    /// 一覧での並び順
    public var sortOrder: Int {
        ModelCategory.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: ModelCategory, rhs: ModelCategory) -> Bool { lhs.sortOrder < rhs.sortOrder }
}

/// モデルの機能
public enum ModelCapability: String, Codable, CaseIterable, Sendable, Hashable {
    case vision
    case tools
    case jsonMode
    case reasoning
    case fim
    case prefixCompletion
    case videoInput
    case audioInput

    public var displayName: String {
        switch self {
        case .vision: return "画像入力"
        case .tools: return "ツール呼び出し"
        case .jsonMode: return "JSON モード"
        case .reasoning: return "思考（推論）"
        case .fim: return "FIM 補完"
        case .prefixCompletion: return "前方補完"
        case .videoInput: return "動画入力"
        case .audioInput: return "音声入力"
        }
    }

    public var systemImage: String {
        switch self {
        case .vision: return "eye"
        case .tools: return "wrench.and.screwdriver"
        case .jsonMode: return "curlybraces"
        case .reasoning: return "brain"
        case .fim: return "text.insert"
        case .prefixCompletion: return "text.append"
        case .videoInput: return "video"
        case .audioInput: return "mic"
        }
    }
}
