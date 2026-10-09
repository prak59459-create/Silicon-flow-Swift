import Foundation

/// 料金の単位
public enum PriceUnit: String, Codable, Sendable, Hashable {
    case perMillionTokens
    case perImage
    case perVideo
    case perMillionBytes
    case perSecond
    case perRequest
    case unknown

    public var displayName: String {
        switch self {
        case .perMillionTokens: return "100万トークンあたり"
        case .perImage: return "1枚あたり"
        case .perVideo: return "1本あたり"
        case .perMillionBytes: return "100万バイトあたり"
        case .perSecond: return "1秒あたり"
        case .perRequest: return "1回あたり"
        case .unknown: return ""
        }
    }

    /// 一覧用の短い表記
    public var shortName: String {
        switch self {
        case .perMillionTokens: return "/M"
        case .perImage: return "/枚"
        case .perVideo: return "/本"
        case .perMillionBytes: return "/MB"
        case .perSecond: return "/秒"
        case .perRequest: return "/回"
        case .unknown: return ""
        }
    }

    /// 公式サイトの表記（"/ M Tokens" "/ Image" など）から判定します。
    public static func parse(_ text: String?) -> PriceUnit {
        guard let text = text?.lowercased(), !text.isEmpty else { return .unknown }
        if text.contains("token") { return .perMillionTokens }
        if text.contains("image") || text.contains("张") || text.contains("pic") { return .perImage }
        if text.contains("video") || text.contains("条") { return .perVideo }
        if text.contains("byte") { return .perMillionBytes }
        if text.contains("second") || text.contains("秒") { return .perSecond }
        if text.contains("request") || text.contains("次") { return .perRequest }
        return .unknown
    }
}

/// カタログ 1 件（価格・パラメータ数・コンテキスト長など）
public struct CatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String?
    public var category: ModelCategory?
    public var inputPrice: Double?
    public var outputPrice: Double?
    public var currency: Currency?
    public var unit: PriceUnit?
    public var totalParamsB: Double?
    public var activeParamsB: Double?
    public var contextLength: Int?
    public var maxOutputTokens: Int?
    public var capabilities: [ModelCapability]?
    public var tags: [String]?
    public var isFree: Bool?
    /// 贈与残高（無料クレジット）では使えず、チャージ残高が必要
    public var requiresChargedBalance: Bool?
    /// 実名認証が必要
    public var requiresRealName: Bool?
    public var summary: String?
    public var releaseDate: String?
    public var deprecated: Bool?
    /// 提供終了（予定）日 "yyyy-MM-dd"
    public var deprecationDate: String?
    /// 価格の出どころ（例: "SiliconFlow公式サイト"）
    public var priceSource: String?
    /// パラメータ数の出どころ
    public var paramsSource: String?

    public init(id: String) {
        self.id = id
    }

    public var parameters: ParameterCount? {
        let count = ParameterCount(totalB: totalParamsB, activeB: activeParamsB)
        return count.isEmpty ? nil : count
    }

    public var hasPrice: Bool { inputPrice != nil || outputPrice != nil }

    /// 無料か（明示されていない場合は価格が 0 かどうかで判定）
    public var effectiveIsFree: Bool {
        if let isFree { return isFree }
        guard hasPrice else { return false }
        return (inputPrice ?? 0) == 0 && (outputPrice ?? 0) == 0
    }

    public func has(_ capability: ModelCapability) -> Bool {
        capabilities?.contains(capability) ?? false
    }

    /// 空いている項目を `other` の値で埋めます（自分の値が優先）。
    public func filling(from other: CatalogEntry) -> CatalogEntry {
        var merged = self
        merged.displayName = displayName ?? other.displayName
        merged.category = category ?? other.category
        if !hasPrice, other.hasPrice {
            merged.inputPrice = other.inputPrice
            merged.outputPrice = other.outputPrice
            merged.currency = other.currency
            merged.unit = other.unit
            merged.priceSource = other.priceSource
            merged.isFree = isFree ?? other.isFree
        } else {
            merged.currency = currency ?? other.currency
            merged.unit = unit ?? other.unit
            merged.isFree = isFree ?? other.isFree
        }
        if totalParamsB == nil, activeParamsB == nil, other.parameters != nil {
            merged.totalParamsB = other.totalParamsB
            merged.activeParamsB = other.activeParamsB
            merged.paramsSource = other.paramsSource
        } else if totalParamsB == nil || activeParamsB == nil {
            merged.totalParamsB = totalParamsB ?? other.totalParamsB
            merged.activeParamsB = activeParamsB ?? other.activeParamsB
        }
        merged.contextLength = contextLength ?? other.contextLength
        merged.maxOutputTokens = maxOutputTokens ?? other.maxOutputTokens
        merged.capabilities = Self.union(capabilities, other.capabilities)
        merged.tags = tags ?? other.tags
        merged.requiresChargedBalance = requiresChargedBalance ?? other.requiresChargedBalance
        merged.requiresRealName = requiresRealName ?? other.requiresRealName
        merged.summary = summary ?? other.summary
        merged.releaseDate = releaseDate ?? other.releaseDate
        merged.deprecated = deprecated ?? other.deprecated
        merged.deprecationDate = deprecationDate ?? other.deprecationDate
        return merged
    }

    /// 価格以外の情報だけを補います（"Pro/" 版に通常版の情報を流用するとき用）。
    public func fillingNonPrice(from other: CatalogEntry) -> CatalogEntry {
        var donor = other
        donor.inputPrice = nil
        donor.outputPrice = nil
        donor.isFree = nil
        donor.priceSource = nil
        donor.requiresChargedBalance = nil
        return filling(from: donor)
    }

    private static func union(_ lhs: [ModelCapability]?, _ rhs: [ModelCapability]?) -> [ModelCapability]? {
        guard lhs != nil || rhs != nil else { return nil }
        var result: [ModelCapability] = []
        for capability in (lhs ?? []) + (rhs ?? []) where !result.contains(capability) {
            result.append(capability)
        }
        return result
    }
}
