import Foundation

/// 情報源ごとの取得結果（画面に「どこから取ったか」を出すため）
public struct CatalogSourceStatus: Sendable, Equatable, Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var succeeded: Bool
    public var entryCount: Int
    public var message: String?
    public var fetchedAt: Date?

    public init(name: String, succeeded: Bool, entryCount: Int = 0, message: String? = nil, fetchedAt: Date? = nil) {
        self.name = name
        self.succeeded = succeeded
        self.entryCount = entryCount
        self.message = message
        self.fetchedAt = fetchedAt
    }
}

/// どの情報源を使うか
public struct CatalogSourceOptions: Sendable, Equatable, Codable {
    public var useRemoteCatalog: Bool
    public var useOfficialSite: Bool
    public var useModelsDev: Bool

    public init(useRemoteCatalog: Bool = true, useOfficialSite: Bool = true, useModelsDev: Bool = true) {
        self.useRemoteCatalog = useRemoteCatalog
        self.useOfficialSite = useOfficialSite
        self.useModelsDev = useModelsDev
    }
}

/// あるリージョンのカタログの状態
public struct CatalogSnapshot: Sendable, Codable {
    public var region: APIRegion
    public var entries: [CatalogEntry]
    public var statuses: [CatalogSourceStatus]
    public var updatedAt: Date?
    /// 同梱データだけ（まだネットから取得していない）
    public var isBundledOnly: Bool

    public init(region: APIRegion, entries: [CatalogEntry], statuses: [CatalogSourceStatus], updatedAt: Date?, isBundledOnly: Bool) {
        self.region = region
        self.entries = entries
        self.statuses = statuses
        self.updatedAt = updatedAt
        self.isBundledOnly = isBundledOnly
    }

    public func isStale(now: Date = Date(), maxAge: TimeInterval = 12 * 3600) -> Bool {
        guard let updatedAt, !isBundledOnly else { return true }
        return now.timeIntervalSince(updatedAt) > maxAge
    }
}

/// 価格・パラメータ数のカタログを複数の情報源から集めて統合します。
///
/// 優先順位: 公式サイト（中国版のみ）→ GitHub カタログ → models.dev（GitHub が使えないとき）→ 同梱データ
public actor CatalogService {
    private let fetcher: WebFetcher
    private let cache: DiskCache
    private let remoteURLs: [URL]
    private var memory: [APIRegion: CatalogSnapshot] = [:]

    public init(fetcher: WebFetcher = WebFetcher(), cache: DiskCache = .default(), remoteURLs: [URL] = RemoteCatalogClient.defaultURLs) {
        self.fetcher = fetcher
        self.cache = cache
        self.remoteURLs = remoteURLs
    }

    /// すぐに使えるカタログ（メモリ → ディスク → 同梱データの順）
    public func current(region: APIRegion) -> CatalogSnapshot {
        if let snapshot = memory[region] { return snapshot }
        if let cached = cache.load(CatalogSnapshot.self, name: Self.cacheName(region)), !cached.entries.isEmpty {
            memory[region] = cached
            return cached
        }
        let bundled = Self.bundledSnapshot(region: region)
        memory[region] = bundled
        return bundled
    }

    /// ネットから最新の情報を取り直します（失敗しても例外は出さず、使えた情報源だけで作ります）。
    public func refresh(region: APIRegion, options: CatalogSourceOptions = CatalogSourceOptions()) async -> CatalogSnapshot {
        let now = Date()
        var layers: [[CatalogEntry]] = []
        var statuses: [CatalogSourceStatus] = []

        async let officialTask = fetchOfficial(enabled: options.useOfficialSite && region == .china)
        async let remoteTask = fetchRemote(enabled: options.useRemoteCatalog, region: region)
        let official = await officialTask
        let remote = await remoteTask

        if let official {
            statuses.append(official.status)
            if !official.entries.isEmpty { layers.append(official.entries) }
        }
        if let remote {
            statuses.append(remote.status)
            if !remote.entries.isEmpty { layers.append(remote.entries) }
        }
        let remoteUsable = !(remote?.entries.isEmpty ?? true)
        if options.useModelsDev, !remoteUsable {
            let modelsDev = await fetchModelsDev(region: region)
            statuses.append(modelsDev.status)
            if !modelsDev.entries.isEmpty { layers.append(modelsDev.entries) }
        }
        let fetchedAny = !layers.isEmpty
        let bundled = BundledCatalog.document?.entries(for: region) ?? []
        layers.append(bundled)
        statuses.append(CatalogSourceStatus(name: BundledCatalog.sourceName, succeeded: !bundled.isEmpty, entryCount: bundled.count, message: BundledCatalog.generatedAt.map { "作成: \($0)" }))

        let snapshot = CatalogSnapshot(
            region: region,
            entries: CatalogMerger.merge(layers),
            statuses: statuses,
            updatedAt: fetchedAny ? now : current(region: region).updatedAt,
            isBundledOnly: !fetchedAny
        )
        if fetchedAny {
            memory[region] = snapshot
            cache.save(snapshot, name: Self.cacheName(region))
        } else if memory[region]?.isBundledOnly ?? true {
            memory[region] = snapshot
        }
        return fetchedAny ? snapshot : current(region: region).withStatuses(statuses)
    }

    public func clearCache() {
        memory.removeAll()
        for region in APIRegion.allCases { cache.remove(name: Self.cacheName(region)) }
    }

    // MARK: - 各情報源

    struct SourceResult: Sendable {
        var entries: [CatalogEntry]
        var status: CatalogSourceStatus
    }

    private func fetchOfficial(enabled: Bool) async -> SourceResult? {
        guard enabled else { return nil }
        let name = OfficialPricingScraper.sourceName
        do {
            let html = try await fetcher.get(OfficialPricingScraper.pageURL, accept: "text/html")
            let entries = OfficialPricingScraper.parse(html: html)
            let message = entries.isEmpty ? "ページの形式が変わったため読み取れませんでした" : nil
            return SourceResult(entries: entries, status: CatalogSourceStatus(name: name, succeeded: !entries.isEmpty, entryCount: entries.count, message: message, fetchedAt: Date()))
        } catch {
            return SourceResult(entries: [], status: failure(name, error))
        }
    }

    private func fetchRemote(enabled: Bool, region: APIRegion) async -> SourceResult? {
        guard enabled else { return nil }
        let name = RemoteCatalogClient.sourceName
        do {
            let document = try await RemoteCatalogClient(fetcher: fetcher, urls: remoteURLs).fetch()
            let entries = document.entries(for: region)
            let message = document.generatedAt.map { "作成: \($0)" }
            return SourceResult(entries: entries, status: CatalogSourceStatus(name: name, succeeded: !entries.isEmpty, entryCount: entries.count, message: message, fetchedAt: Date()))
        } catch {
            return SourceResult(entries: [], status: failure(name, error))
        }
    }

    private func fetchModelsDev(region: APIRegion) async -> SourceResult {
        let name = ModelsDevCatalog.sourceName
        do {
            let data = try await fetcher.get(ModelsDevCatalog.apiURL, accept: "application/json")
            let entries = ModelsDevCatalog.parse(apiJSON: data, region: region)
            return SourceResult(entries: entries, status: CatalogSourceStatus(name: name, succeeded: !entries.isEmpty, entryCount: entries.count, fetchedAt: Date()))
        } catch {
            return SourceResult(entries: [], status: failure(name, error))
        }
    }

    private func failure(_ name: String, _ error: Error) -> CatalogSourceStatus {
        let wrapped = SiliconFlowError.wrap(error)
        return CatalogSourceStatus(name: name, succeeded: false, message: wrapped.diagnosis.title)
    }

    static func cacheName(_ region: APIRegion) -> String { "catalog-\(region.rawValue)" }

    static func bundledSnapshot(region: APIRegion) -> CatalogSnapshot {
        let entries = BundledCatalog.document?.entries(for: region) ?? []
        let status = CatalogSourceStatus(name: BundledCatalog.sourceName, succeeded: !entries.isEmpty, entryCount: entries.count, message: BundledCatalog.generatedAt.map { "作成: \($0)" })
        return CatalogSnapshot(region: region, entries: entries, statuses: [status], updatedAt: nil, isBundledOnly: true)
    }
}

extension CatalogSnapshot {
    func withStatuses(_ statuses: [CatalogSourceStatus]) -> CatalogSnapshot {
        var copy = self
        copy.statuses = statuses
        return copy
    }
}

/// アプリに同梱したカタログ（オフラインでも価格・パラメータ数を表示するため）
public enum BundledCatalog {
    public static let sourceName = "同梱データ"

    public static let document: CatalogDocument? = {
        try? CatalogDocument.decode(Data(BundledCatalogSnapshot.json.utf8))
    }()

    public static var generatedAt: String? { document?.generatedAt }
}
