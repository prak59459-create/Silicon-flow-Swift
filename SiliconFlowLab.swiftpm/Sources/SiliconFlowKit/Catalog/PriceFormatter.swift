import Foundation

/// 価格の表示
public enum PriceFormatter {
    /// 一覧の行に出す短い表記（例: "2元 / 8元 /M"、"無料"、"$0.27/$1.1 /M"）
    public static func compact(_ entry: CatalogEntry?) -> String {
        guard let entry, entry.hasPrice else { return "価格不明" }
        if entry.effectiveIsFree { return "無料" }
        let currency = entry.currency ?? .cny
        let unit = (entry.unit ?? .perMillionTokens).shortName
        switch (entry.inputPrice, entry.outputPrice) {
        case let (input?, output?) where input != output && (entry.unit ?? .perMillionTokens) == .perMillionTokens:
            return "\(currency.format(input)) / \(currency.format(output))\(unit)"
        case let (_, output?):
            return "\(currency.format(output))\(unit)"
        case let (input?, nil):
            return "\(currency.format(input))\(unit)"
        default:
            return "価格不明"
        }
    }

    /// 詳細画面の行（タイトル, 値）
    public static func detailRows(_ entry: CatalogEntry?, rates: ExchangeRates?, showYen: Bool) -> [(String, String)] {
        guard let entry, entry.hasPrice else { return [("料金", "不明（公式サイトで確認してください）")] }
        if entry.effectiveIsFree { return [("料金", "無料")] }
        let currency = entry.currency ?? .cny
        let unit = entry.unit ?? .perMillionTokens
        var rows: [(String, String)] = []
        let isTokenPricing = unit == .perMillionTokens
        if isTokenPricing, let input = entry.inputPrice {
            rows.append(("入力", line(input, currency: currency, unit: unit, rates: rates, showYen: showYen)))
        }
        if let output = entry.outputPrice {
            rows.append((isTokenPricing ? "出力" : "料金", line(output, currency: currency, unit: unit, rates: rates, showYen: showYen)))
        } else if !isTokenPricing, let input = entry.inputPrice {
            rows.append(("料金", line(input, currency: currency, unit: unit, rates: rates, showYen: showYen)))
        }
        return rows
    }

    static func line(_ amount: Double, currency: Currency, unit: PriceUnit, rates: ExchangeRates?, showYen: Bool) -> String {
        var text = currency.format(amount)
        if !unit.displayName.isEmpty { text += "（\(unit.displayName)）" }
        if showYen, currency != .jpy, let yen = Money(amount: amount, currency: currency).converted(to: .jpy, using: rates) {
            text += " ≈ \(yen.formatted)"
        }
        return text
    }

    /// 並べ替え用の代表価格（出力 → 入力の順）。不明なら nil。
    public static func sortKey(_ entry: CatalogEntry?) -> Double? {
        guard let entry, entry.hasPrice else { return nil }
        if entry.effectiveIsFree { return 0 }
        return entry.outputPrice ?? entry.inputPrice
    }
}

/// コンテキスト長の表示
public enum ContextLengthFormatter {
    /// 例: 131072 → "128K", 1048576 → "1M", 200000 → "200K"
    public static func format(_ tokens: Int?) -> String {
        guard let tokens, tokens > 0 else { return "?" }
        if tokens >= 1_000_000 {
            let divisor: Double = tokens % 1_048_576 == 0 ? 1_048_576 : 1_000_000
            return NumberText.compact(Double(tokens) / divisor, maxFractionDigits: 1) + "M"
        }
        if tokens >= 1000 {
            let divisor: Double = tokens % 1024 == 0 ? 1024 : 1000
            return NumberText.compact((Double(tokens) / divisor).rounded(), maxFractionDigits: 0) + "K"
        }
        return String(tokens)
    }
}
