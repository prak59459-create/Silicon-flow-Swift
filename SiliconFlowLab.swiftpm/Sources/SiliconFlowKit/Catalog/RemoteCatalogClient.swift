import Foundation

/// GitHub に置いたカタログ（GitHub Actions が毎日公式サイト等から自動更新）を取得します。
public struct RemoteCatalogClient: Sendable {
    public static let sourceName = "GitHub カタログ"

    /// 上から順に試します（raw.githubusercontent.com が使えないネットワーク向けに CDN も用意）
    public static let defaultURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/prak59459-create/Silicon-flow-Swift/main/catalog/siliconflow-catalog.json")!,
        URL(string: "https://cdn.jsdelivr.net/gh/prak59459-create/Silicon-flow-Swift@main/catalog/siliconflow-catalog.json")!,
    ]

    let fetcher: WebFetcher
    let urls: [URL]

    public init(fetcher: WebFetcher = WebFetcher(), urls: [URL] = RemoteCatalogClient.defaultURLs) {
        self.fetcher = fetcher
        self.urls = urls
    }

    public func fetch() async throws -> CatalogDocument {
        var lastError: Error = SiliconFlowError(kind: .unknown, endpoint: Self.sourceName)
        for url in urls {
            do {
                let data = try await fetcher.get(url, accept: "application/json")
                let document = try CatalogDocument.decode(data)
                guard document.schemaVersion <= CatalogDocument.currentSchemaVersion else {
                    lastError = SiliconFlowError(kind: .decodingFailed, endpoint: "GET \(url.host ?? "")", underlying: "未対応のカタログ形式 v\(document.schemaVersion)")
                    continue
                }
                return document
            } catch {
                if (error as? SiliconFlowError)?.kind == .cancelled { throw error }
                lastError = error
            }
        }
        throw lastError
    }
}
