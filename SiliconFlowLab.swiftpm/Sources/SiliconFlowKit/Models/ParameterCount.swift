import Foundation

/// モデルのパラメータ数（単位: 10 億 = B）
public struct ParameterCount: Codable, Hashable, Sendable {
    /// 総パラメータ数
    public var totalB: Double?
    /// MoE の場合、1 トークンあたりに使われるパラメータ数
    public var activeB: Double?

    public init(totalB: Double? = nil, activeB: Double? = nil) {
        self.totalB = totalB
        self.activeB = activeB
    }

    public var isMoE: Bool { activeB != nil }
    public var isEmpty: Bool { totalB == nil && activeB == nil }

    /// 足りない方を他の情報で補います。
    public func filling(from other: ParameterCount?) -> ParameterCount {
        guard let other else { return self }
        return ParameterCount(totalB: totalB ?? other.totalB, activeB: activeB ?? other.activeB)
    }

    /// 表示用（例: "8.2B"、"235B（アクティブ 22B）"）
    public var displayText: String {
        switch (totalB, activeB) {
        case let (total?, active?): return "\(Self.format(total))（アクティブ \(Self.format(active))）"
        case let (total?, nil): return Self.format(total)
        case let (nil, active?): return "アクティブ \(Self.format(active))"
        default: return "不明"
        }
    }

    /// 短い表示（一覧の行用）
    public var compactText: String {
        switch (totalB, activeB) {
        case let (total?, active?): return "\(Self.format(total))/A\(Self.format(active))"
        case let (total?, nil): return Self.format(total)
        case let (nil, active?): return "A\(Self.format(active))"
        default: return "?"
        }
    }

    /// 10 億単位の数値を "1.03T" "235B" "8.2B" "0.6B" のように整形します。
    public static func format(_ billions: Double) -> String {
        guard billions.isFinite, billions > 0 else { return "?" }
        if billions >= 1000 {
            return NumberText.compact(billions / 1000, maxFractionDigits: 2) + "T"
        }
        if billions >= 10 {
            return NumberText.compact(billions.rounded(), maxFractionDigits: 0) + "B"
        }
        if billions >= 1 {
            return NumberText.compact(billions, maxFractionDigits: 1) + "B"
        }
        return NumberText.compact(billions, maxFractionDigits: 2) + "B"
    }

    /// パラメータの個数（例: 8_190_735_360）から作ります。
    public static func fromRawCount(_ count: Int64) -> ParameterCount? {
        guard count > 0 else { return nil }
        let billions = Double(count) / 1_000_000_000
        // 0.01B（1000万）単位に丸める（表示にはそれ以上の精度は不要）
        return ParameterCount(totalB: (billions * 100).rounded() / 100)
    }
}
