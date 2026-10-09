import Foundation

/// API クライアントの設定
public struct ClientConfiguration: Sendable, Equatable {
    public var region: APIRegion
    public var apiKey: String
    /// 独自のエンドポイント（プロキシ等）を使う場合だけ指定します。
    public var customBaseURL: URL?
    /// 1 リクエストのタイムアウト（秒）
    public var requestTimeout: TimeInterval
    public var userAgent: String

    public static let defaultUserAgent = "SiliconFlowLab/1.0 (Swift Playgrounds)"

    public init(
        region: APIRegion,
        apiKey: String,
        customBaseURL: URL? = nil,
        requestTimeout: TimeInterval = 120,
        userAgent: String = ClientConfiguration.defaultUserAgent
    ) {
        self.region = region
        self.apiKey = apiKey
        self.customBaseURL = customBaseURL
        self.requestTimeout = requestTimeout
        self.userAgent = userAgent
    }

    public var baseURL: URL { customBaseURL ?? region.defaultBaseURL }

    /// 実際に送るキー（前後の空白や "Bearer " を除去したもの）
    public var sanitizedAPIKey: String { APIKeyValidator.sanitize(apiKey) }
}

/// ベース URL の入力を正規化します。
public enum BaseURLNormalizer {
    public enum Failure: Error, Equatable {
        case empty
        case invalid
        case insecure
    }

    /// 例: "api.example.com" → "https://api.example.com/v1"
    ///     "https://api.example.com/v1/" → "https://api.example.com/v1"
    public static func normalize(_ input: String) -> Result<URL, Failure> {
        var text = TextSanitizer.trimmed(TextSanitizer.halfWidth(input))
        guard !text.isEmpty else { return .failure(.empty) }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        for suffix in ["/chat/completions", "/models"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty, !host.contains(" ")
        else { return .failure(.invalid) }
        let isLocal = host == "localhost" || host.hasPrefix("127.") || host.hasSuffix(".local")
        guard scheme == "https" || (scheme == "http" && isLocal) else { return .failure(.insecure) }
        if components.path.isEmpty { components.path = "/v1" }
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return .failure(.invalid) }
        return .success(url)
    }
}
