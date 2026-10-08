import Foundation

/// `POST /audio/speech` のリクエスト（音声合成）
public struct SpeechRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var input: String
    /// 例: "FunAudioLLM/CosyVoice2-0.5B:alex"
    public var voice: String?
    public var responseFormat: String
    public var speed: Double?
    public var gain: Double?
    public var stream: Bool

    public init(model: String, input: String, voice: String?, responseFormat: String = "mp3", speed: Double? = nil, gain: Double? = nil) {
        self.model = model
        self.input = input
        self.voice = voice
        self.responseFormat = responseFormat
        self.speed = speed
        self.gain = gain
        self.stream = false
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case responseFormat = "response_format"
        case speed
        case gain
        case stream
    }

    /// システム音声の名前（モデル ID と組み合わせて使います）
    public static let presetVoices = ["alex", "anna", "bella", "benjamin", "charles", "claire", "david", "diana"]

    /// "モデルID:声" 形式の voice 値
    public static func voiceID(model: String, voice: String) -> String { "\(model):\(voice)" }
}

/// `POST /audio/transcriptions` のレスポンス（音声認識）
public struct TranscriptionResponse: Decodable, Sendable, Hashable {
    public var text: String
}

/// multipart/form-data の組み立て
public struct MultipartFormData: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "SiliconFlowLab-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    public mutating func addFile(name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.escape(name))\"; filename=\"\(Self.escape(fileName))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    public func finalized() -> Data {
        var result = body
        result.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return result
    }

    private mutating func append(_ text: String) {
        body.append(contentsOf: text.utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    /// 拡張子から MIME タイプを推定します。
    public static func audioMimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a", "mp4": return "audio/mp4"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}
