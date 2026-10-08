import Foundation

/// ロケールに左右されない数値の文字列化。
///
/// NumberFormatter は端末の地域設定で小数点記号が変わるため、
/// テストで結果を固定できるよう自前で整形します。
public enum NumberText {
    /// 小数点以下 `maxFractionDigits` 桁で丸め、末尾の 0 を取り除きます。
    /// 例: compact(2.50) → "2.5", compact(3.0) → "3"
    public static func compact(_ value: Double, maxFractionDigits: Int = 6) -> String {
        guard value.isFinite else { return "-" }
        let digits = max(0, min(maxFractionDigits, 10))
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }

    /// 小数点以下の桁数を固定します。例: fixed(2.5, 2) → "2.50"
    public static func fixed(_ value: Double, fractionDigits: Int) -> String {
        guard value.isFinite else { return "-" }
        let digits = max(0, min(fractionDigits, 10))
        var text = String(format: "%.\(digits)f", value)
        if text.hasPrefix("-"), Double(text) == 0 { text.removeFirst() }
        return text
    }

    /// 金額向け：小さな値でも有効数字が残るように桁数を自動調整します。
    /// 例: 2 → "2.00", 0.042 → "0.042", 0.0001234 → "0.000123"
    public static func money(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        if magnitude >= 100 { return fixed(value, fractionDigits: 0) }
        if magnitude >= 0.1 { return fixed(value, fractionDigits: 2) }
        // 0.1 未満は有効数字 3 桁
        let exponent = Int(floor(log10(magnitude)))
        let digits = min(10, max(2, -exponent + 2))
        return compact(value, maxFractionDigits: digits)
    }

    /// 3 桁区切り（例: 1234567 → "1,234,567"）
    public static func grouped(_ value: Int) -> String {
        let negative = value < 0
        let digits = String(value.magnitude)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return negative ? "-" + result : result
    }
}
