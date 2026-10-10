import Foundation

/// 残高の取得結果
///
/// 残高照会 API（`GET /user/info`）は中国版で 2026-08-14 に停止しました。
/// 取れないことも普通の状態として扱い、キーの確認・モデル一覧・チャットの妨げにしません。
public enum BalanceLookup: Sendable, Equatable {
    case available(UserInfo)
    /// API が提供終了した、または存在しない（HTTP 410 / コード 20092 / 404）
    case unsupported
    /// 一時的な失敗など（キーが無効なときもここに入ります）
    case failed(SiliconFlowError)

    public init(error: Error, region: APIRegion?) {
        let wrapped = SiliconFlowError.wrap(error, region: region)
        self = Self.meansUnsupported(wrapped) ? .unsupported : .failed(wrapped)
    }

    /// 「この接続先では残高 API が使えない」と判断できる失敗か
    public static func meansUnsupported(_ error: SiliconFlowError) -> Bool {
        error.kind == .endpointRetired || error.kind == .endpointNotFound
    }

    public var userInfo: UserInfo? {
        if case .available(let info) = self { return info }
        return nil
    }
}

extension SiliconFlowClient {
    /// 残高を参考として取得します。失敗しても例外は投げません。
    public func lookUpBalance() async -> BalanceLookup {
        do {
            return .available(try await userInfo())
        } catch {
            return BalanceLookup(error: error, region: region)
        }
    }
}

/// 残高 API が使えないと分かった接続先を覚えておき、毎回むだに呼ばないようにします。
///
/// 一定期間（既定 7 日）たったら、代わりの API の再開に備えて 1 回だけ確かめ直します。
public struct BalanceSupportRecord: Codable, Sendable, Equatable {
    public static let recheckInterval: TimeInterval = 7 * 24 * 60 * 60

    /// 接続先 URL → 使えないと分かった日時
    public private(set) var unsupportedSince: [String: Date]

    public init(unsupportedSince: [String: Date] = [:]) {
        self.unsupportedSince = unsupportedSince
    }

    /// 残高 API を呼ぶべきか
    public func shouldLookUp(baseURL: URL, now: Date = Date()) -> Bool {
        guard let since = unsupportedSince[Self.key(baseURL)] else { return true }
        return now.timeIntervalSince(since) >= Self.recheckInterval || now < since
    }

    /// 結果を記録します。変化があれば true。
    @discardableResult
    public mutating func record(_ lookup: BalanceLookup, baseURL: URL, now: Date = Date()) -> Bool {
        let key = Self.key(baseURL)
        switch lookup {
        case .unsupported:
            unsupportedSince[key] = now
            return true
        case .available:
            return unsupportedSince.removeValue(forKey: key) != nil
        case .failed:
            // 一時的な失敗かもしれないので記録しません
            return false
        }
    }

    static func key(_ baseURL: URL) -> String {
        var text = baseURL.absoluteString.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
