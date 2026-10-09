import Foundation

/// 使用量と価格から料金を計算します。
public enum CostEstimator {
    /// トークン課金のモデルの料金（無料なら 0、価格不明なら nil）
    public static func cost(usage: Usage?, entry: CatalogEntry?) -> Money? {
        guard let usage, let entry, entry.hasPrice else { return nil }
        let currency = entry.currency ?? .cny
        if entry.effectiveIsFree { return Money(amount: 0, currency: currency) }
        guard (entry.unit ?? .perMillionTokens) == .perMillionTokens else { return nil }
        let prompt = Double(usage.promptTokens ?? 0)
        let completion = Double(usage.completionTokens ?? 0)
        let inputPrice = entry.inputPrice ?? entry.outputPrice ?? 0
        let outputPrice = entry.outputPrice ?? entry.inputPrice ?? 0
        let amount = prompt * inputPrice / 1_000_000 + completion * outputPrice / 1_000_000
        return Money(amount: amount, currency: currency)
    }

    /// 枚数・本数課金のモデルの料金
    public static func cost(units: Int, entry: CatalogEntry?) -> Money? {
        guard let entry, let price = entry.outputPrice ?? entry.inputPrice else { return nil }
        let unit = entry.unit ?? .unknown
        guard unit == .perImage || unit == .perVideo || unit == .perRequest else { return nil }
        return Money(amount: price * Double(units), currency: entry.currency ?? .cny)
    }

    /// 埋め込み・リランク（入力トークンのみ課金）の料金
    public static func cost(inputTokens: Int, entry: CatalogEntry?) -> Money? {
        guard let entry, entry.hasPrice else { return nil }
        let currency = entry.currency ?? .cny
        if entry.effectiveIsFree { return Money(amount: 0, currency: currency) }
        guard let price = entry.inputPrice ?? entry.outputPrice else { return nil }
        return Money(amount: Double(inputTokens) * price / 1_000_000, currency: currency)
    }
}
