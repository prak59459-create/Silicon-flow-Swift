import Foundation

/// GitHub で配布するカタログファイル（catalog/siliconflow-catalog.json）の形式
public struct CatalogDocument: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// ISO8601 形式の作成日時
    public var generatedAt: String?
    /// "cn"（中国版）/ "global"（国際版）
    public var regions: [String: RegionCatalog]
    /// 各情報源の取得結果（参考情報）
    public var sources: [String]?

    public init(schemaVersion: Int = CatalogDocument.currentSchemaVersion, generatedAt: String? = nil, regions: [String: RegionCatalog], sources: [String]? = nil) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.regions = regions
        self.sources = sources
    }

    public func entries(for region: APIRegion) -> [CatalogEntry] {
        regions[region.rawValue]?.entries ?? []
    }

    public var generatedDate: Date? {
        guard let generatedAt else { return nil }
        return ISO8601.parse(generatedAt)
    }

    public static func decode(_ data: Data) throws -> CatalogDocument {
        try JSONDecoder().decode(CatalogDocument.self, from: data)
    }

    public func encoded(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct RegionCatalog: Codable, Sendable, Equatable {
    public var entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
    }
}

/// 日付の変換（Linux と Apple で同じ結果になる実装）
public enum ISO8601 {
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: text)
    }
}

/// モデル ID からカタログを引く索引
public struct CatalogIndex: Sendable {
    private var exact: [String: CatalogEntry] = [:]
    private var base: [String: CatalogEntry] = [:]

    public init(entries: [CatalogEntry]) {
        for entry in entries {
            let key = Self.key(entry.id)
            if let existing = exact[key] {
                exact[key] = existing.filling(from: entry)
            } else {
                exact[key] = entry
            }
            let baseKey = Self.key(ModelClassifier.strippedPrefixes(entry.id))
            if !ModelClassifier.isProVariant(entry.id) || base[baseKey] == nil {
                base[baseKey] = entry
            }
        }
    }

    public var count: Int { exact.count }
    public var allEntries: [CatalogEntry] { Array(exact.values) }

    /// 完全一致で探し、無ければ "Pro/" 等を外した版から価格以外の情報を流用します。
    public func lookup(_ modelID: String) -> CatalogEntry? {
        let key = Self.key(modelID)
        let baseKey = Self.key(ModelClassifier.strippedPrefixes(modelID))
        let fallback = base[baseKey]
        if var entry = exact[key] {
            if let fallback, fallback.id != entry.id { entry = entry.fillingNonPrice(from: fallback) }
            return entry
        }
        guard let fallback else { return nil }
        var entry = CatalogEntry(id: modelID)
        entry = entry.fillingNonPrice(from: fallback)
        return entry
    }

    static func key(_ id: String) -> String { id.lowercased() }
}

/// 複数の情報源のカタログを統合します。
public enum CatalogMerger {
    /// 先頭ほど優先度が高い。各項目は優先度の高い情報源の値を使い、無ければ次を使います。
    public static func merge(_ layers: [[CatalogEntry]]) -> [CatalogEntry] {
        var order: [String] = []
        var merged: [String: CatalogEntry] = [:]
        for layer in layers {
            for entry in layer {
                let key = CatalogIndex.key(entry.id)
                if let existing = merged[key] {
                    merged[key] = existing.filling(from: entry)
                } else {
                    merged[key] = entry
                    order.append(key)
                }
            }
        }
        return order.compactMap { merged[$0] }
    }
}
