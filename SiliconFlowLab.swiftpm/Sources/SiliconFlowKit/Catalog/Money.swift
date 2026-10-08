import Foundation

/// 通貨
public enum Currency: String, Codable, Sendable, CaseIterable {
    case cny = "CNY"
    case usd = "USD"
    case jpy = "JPY"

    /// 日本語 UI 向けの表記。人民元と日本円の「¥」を取り違えないよう人民元は「元」で表します。
    public func format(_ amount: Double) -> String {
        switch self {
        case .cny: return NumberText.money(amount) + "元"
        case .usd: return "$" + NumberText.money(amount)
        case .jpy: return Self.yen(amount)
        }
    }

    public var displayName: String {
        switch self {
        case .cny: return "人民元"
        case .usd: return "米ドル"
        case .jpy: return "日本円"
        }
    }

    private static func yen(_ amount: Double) -> String {
        if amount == 0 { return "0円" }
        if abs(amount) < 1 { return NumberText.money(amount) + "円" }
        if abs(amount) < 100 { return NumberText.compact(amount, maxFractionDigits: 1) + "円" }
        return NumberText.grouped(Int(amount.rounded())) + "円"
    }

    /// 公式サイトの通貨記号から通貨を推定します。
    public static func from(symbol: String?) -> Currency? {
        guard let symbol = symbol?.trimmingCharacters(in: .whitespaces).uppercased(), !symbol.isEmpty else { return nil }
        switch symbol {
        case "¥", "￥", "CNY", "RMB", "元": return .cny
        case "$", "USD", "US$": return .usd
        case "JPY", "円": return .jpy
        default: return nil
        }
    }
}

/// 金額
public struct Money: Codable, Hashable, Sendable {
    public var amount: Double
    public var currency: Currency

    public init(amount: Double, currency: Currency) {
        self.amount = amount
        self.currency = currency
    }

    public var formatted: String { currency.format(amount) }

    public static func + (lhs: Money, rhs: Money) -> Money? {
        guard lhs.currency == rhs.currency else { return nil }
        return Money(amount: lhs.amount + rhs.amount, currency: lhs.currency)
    }

    /// 為替レートで換算します。
    public func converted(to target: Currency, using rates: ExchangeRates?) -> Money? {
        if target == currency { return self }
        guard let rate = rates?.rate(from: currency, to: target) else { return nil }
        return Money(amount: amount * rate, currency: target)
    }
}
