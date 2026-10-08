import Foundation

/// `GET /user/info` のアカウント情報（残高など）
public struct UserInfo: Sendable, Equatable {
    public var id: String?
    public var name: String?
    public var email: String?
    public var status: String?
    public var isAdmin: Bool?
    /// 贈与残高（無料クレジット）
    public var balance: Double?
    /// チャージ残高
    public var chargeBalance: Double?
    /// 合計残高
    public var totalBalance: Double?

    public init(
        id: String? = nil, name: String? = nil, email: String? = nil, status: String? = nil, isAdmin: Bool? = nil,
        balance: Double? = nil, chargeBalance: Double? = nil, totalBalance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.status = status
        self.isAdmin = isAdmin
        self.balance = balance
        self.chargeBalance = chargeBalance
        self.totalBalance = totalBalance
    }

    /// 合計残高（無ければ内訳から計算）
    public var effectiveTotal: Double? {
        if let totalBalance { return totalBalance }
        switch (balance, chargeBalance) {
        case let (gift?, charge?): return gift + charge
        case let (gift?, nil): return gift
        case let (nil, charge?): return charge
        default: return nil
        }
    }

    public var isNormalStatus: Bool {
        guard let status = status?.lowercased(), !status.isEmpty else { return true }
        return status == "normal" || status == "active"
    }

    /// レスポンス本文から読み取ります。`{"code":20000,"data":{...}}` 形式と `data` 直下の両方に対応。
    public static func parse(_ data: Data) -> UserInfo? {
        guard let json = JSONValue.parse(data), let object = json.objectValue else { return nil }
        let payload = object["data"]?.objectValue ?? object
        guard payload["id"] != nil || payload["balance"] != nil || payload["totalBalance"] != nil else { return nil }
        return UserInfo(
            id: payload["id"]?.stringValue,
            name: nonEmpty(payload["name"]?.stringValue),
            email: nonEmpty(payload["email"]?.stringValue),
            status: payload["status"]?.stringValue,
            isAdmin: payload["isAdmin"]?.boolValue,
            balance: payload["balance"]?.doubleValue,
            chargeBalance: payload["chargeBalance"]?.doubleValue,
            totalBalance: payload["totalBalance"]?.doubleValue
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
