import Foundation
import SiliconFlowKit

/// 画面表示用の書式
enum DisplayFormat {
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// 例: 0.42 → "0.42秒"、75 → "1分15秒"
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return NumberText.fixed(seconds, fractionDigits: 2) + "秒" }
        if seconds < 60 { return NumberText.fixed(seconds, fractionDigits: 1) + "秒" }
        let minutes = Int(seconds) / 60
        let rest = Int(seconds) % 60
        return "\(minutes)分\(rest)秒"
    }

    static func tokens(_ count: Int) -> String {
        NumberText.grouped(count)
    }

    static func bytes(_ count: Int) -> String {
        let value = Double(count)
        if value < 1024 { return "\(count) B" }
        if value < 1024 * 1024 { return NumberText.fixed(value / 1024, fractionDigits: 1) + " KB" }
        return NumberText.fixed(value / 1024 / 1024, fractionDigits: 1) + " MB"
    }

    /// 金額と円換算（例: "0.0012元 ≈ 0.02円"）
    static func money(_ money: Money, rates: ExchangeRates?, showYen: Bool) -> String {
        var text = money.formatted
        if showYen, money.currency != .jpy, let yen = money.converted(to: .jpy, using: rates) {
            text += " ≈ \(yen.formatted)"
        }
        return text
    }
}
