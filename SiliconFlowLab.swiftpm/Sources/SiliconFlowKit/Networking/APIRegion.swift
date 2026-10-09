import Foundation

/// SiliconFlow のプラットフォーム（リージョン）。
///
/// 中国版（siliconflow.cn）と国際版（siliconflow.com）はアカウントも API キーも別です。
/// 片方のキーをもう片方で使うと「Token is invalid」（401）になります。
public enum APIRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case china = "cn"
    case international = "global"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .china: return "中国版 (siliconflow.cn)"
        case .international: return "国際版 (siliconflow.com)"
        }
    }

    public var shortName: String {
        switch self {
        case .china: return "中国版"
        case .international: return "国際版"
        }
    }

    public var host: String {
        switch self {
        case .china: return "api.siliconflow.cn"
        case .international: return "api.siliconflow.com"
        }
    }

    public var defaultBaseURL: URL { Self.url("https://\(host)/v1") }

    public var consoleURL: URL {
        switch self {
        case .china: return Self.url("https://cloud.siliconflow.cn")
        case .international: return Self.url("https://cloud.siliconflow.com")
        }
    }

    /// API キー管理ページ
    public var apiKeysURL: URL { consoleURL.appendingPathComponent("account/ak") }

    /// コンソールのモデル一覧ページ
    public var modelsPageURL: URL { consoleURL.appendingPathComponent("models") }

    /// 公式の料金ページ
    public var pricingPageURL: URL {
        switch self {
        case .china: return Self.url("https://siliconflow.cn/pricing")
        case .international: return Self.url("https://www.siliconflow.com/pricing")
        }
    }

    public var docsURL: URL {
        switch self {
        case .china: return Self.url("https://docs.siliconflow.cn/cn/userguide/introduction")
        case .international: return Self.url("https://docs.siliconflow.com/en/userguide/introduction")
        }
    }

    public var errorDocsURL: URL {
        switch self {
        case .china: return Self.url("https://docs.siliconflow.cn/cn/faqs/error-code")
        case .international: return Self.url("https://docs.siliconflow.com/en/faqs/error-code")
        }
    }

    /// 残高・料金の通貨
    public var currency: Currency {
        switch self {
        case .china: return .cny
        case .international: return .usd
        }
    }

    /// もう一方のリージョン
    public var other: APIRegion {
        switch self {
        case .china: return .international
        case .international: return .china
        }
    }

    /// ホスト名からリージョンを推定します（カスタム URL 用）。
    public static func guess(fromHost host: String?) -> APIRegion? {
        guard let host = host?.lowercased() else { return nil }
        if host.hasSuffix("siliconflow.cn") { return .china }
        if host.hasSuffix("siliconflow.com") { return .international }
        return nil
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("Invalid URL literal: \(string)") }
        return url
    }
}
