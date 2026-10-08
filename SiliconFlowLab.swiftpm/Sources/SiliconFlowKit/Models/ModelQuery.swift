import Foundation

/// モデル一覧の絞り込み・並べ替え
public struct ModelQuery: Sendable, Equatable {
    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case recommended
        case name
        case priceLowToHigh
        case priceHighToLow
        case parametersLargeFirst
        case parametersSmallFirst
        case contextLargeFirst
        case newest

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .recommended: return "おすすめ順"
            case .name: return "名前順"
            case .priceLowToHigh: return "安い順"
            case .priceHighToLow: return "高い順"
            case .parametersLargeFirst: return "パラメータ数が多い順"
            case .parametersSmallFirst: return "パラメータ数が少ない順"
            case .contextLargeFirst: return "コンテキストが長い順"
            case .newest: return "新しい順"
            }
        }
    }

    public var searchText: String
    public var category: ModelCategory?
    public var freeOnly: Bool
    public var hideDeprecated: Bool
    public var sort: Sort

    public init(searchText: String = "", category: ModelCategory? = nil, freeOnly: Bool = false, hideDeprecated: Bool = true, sort: Sort = .recommended) {
        self.searchText = searchText
        self.category = category
        self.freeOnly = freeOnly
        self.hideDeprecated = hideDeprecated
        self.sort = sort
    }

    public func apply(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        let filtered = models.filter { model in
            if let category, model.category != category { return false }
            if freeOnly, !model.isFree { return false }
            if hideDeprecated, model.isDeprecated { return false }
            return model.matches(search: searchText)
        }
        return filtered.sorted(by: comparator)
    }

    /// カテゴリ別の件数（サイドバー表示用）
    public static func counts(_ models: [ModelDescriptor]) -> [ModelCategory: Int] {
        var counts: [ModelCategory: Int] = [:]
        for model in models { counts[model.category, default: 0] += 1 }
        return counts
    }

    private var comparator: (ModelDescriptor, ModelDescriptor) -> Bool {
        switch sort {
        case .recommended: return Self.recommended
        case .name: return { $0.id.lowercased() < $1.id.lowercased() }
        case .priceLowToHigh: return { Self.compare($0, $1, PriceFormatter.sortKey($0.catalog), PriceFormatter.sortKey($1.catalog), ascending: true) }
        case .priceHighToLow: return { Self.compare($0, $1, PriceFormatter.sortKey($0.catalog), PriceFormatter.sortKey($1.catalog), ascending: false) }
        case .parametersLargeFirst: return { Self.compare($0, $1, $0.parameters?.totalB ?? $0.parameters?.activeB, $1.parameters?.totalB ?? $1.parameters?.activeB, ascending: false) }
        case .parametersSmallFirst: return { Self.compare($0, $1, $0.parameters?.totalB ?? $0.parameters?.activeB, $1.parameters?.totalB ?? $1.parameters?.activeB, ascending: true) }
        case .contextLargeFirst: return { Self.compare($0, $1, $0.catalog?.contextLength.map(Double.init), $1.catalog?.contextLength.map(Double.init), ascending: false) }
        case .newest: return { ($0.catalog?.releaseDate ?? "", $1.id) > ($1.catalog?.releaseDate ?? "", $0.id) }
        }
    }

    /// カテゴリ順 → 情報が揃っているもの → 名前
    static func recommended(_ lhs: ModelDescriptor, _ rhs: ModelDescriptor) -> Bool {
        if lhs.category != rhs.category { return lhs.category < rhs.category }
        let lhsKnown = lhs.catalog?.hasPrice ?? false
        let rhsKnown = rhs.catalog?.hasPrice ?? false
        if lhsKnown != rhsKnown { return lhsKnown }
        return lhs.id.lowercased() < rhs.id.lowercased()
    }

    /// 値が不明なものは常に最後。同じ値なら名前順。
    static func compare(_ lhs: ModelDescriptor, _ rhs: ModelDescriptor, _ left: Double?, _ right: Double?, ascending: Bool) -> Bool {
        switch (left, right) {
        case let (l?, r?) where l != r: return ascending ? l < r : l > r
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.id.lowercased() < rhs.id.lowercased()
        }
    }
}
