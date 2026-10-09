import Foundation
#if canImport(Security)
import Security
#endif

/// API キーの保存先
public protocol KeyStore: Sendable {
    func load(account: String) -> String?
    @discardableResult func save(_ value: String, account: String) -> Bool
    @discardableResult func delete(account: String) -> Bool
}

/// メモリ上だけに保存（テスト・Linux 用）
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func load(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    public func save(_ value: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        values[account] = value
        return true
    }

    public func delete(account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        values[account] = nil
        return true
    }
}

/// UserDefaults に保存（キーチェーンが使えない環境での予備）
public final class UserDefaultsKeyStore: KeyStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "SiliconFlowLab.secret.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func load(account: String) -> String? { defaults.string(forKey: prefix + account) }

    public func save(_ value: String, account: String) -> Bool {
        defaults.set(value, forKey: prefix + account)
        return true
    }

    public func delete(account: String) -> Bool {
        defaults.removeObject(forKey: prefix + account)
        return true
    }
}

#if canImport(Security)
/// キーチェーンに保存（iPad では基本的にこちらを使います）
public final class KeychainKeyStore: KeyStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.prak59459.SiliconFlowLab") {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        var addQuery = query
        for (key, value) in attributes { addQuery[key] = value }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    public func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
#endif

/// キーチェーンを優先し、失敗したら予備の保存先を使う保存先
public final class ResilientKeyStore: KeyStore, @unchecked Sendable {
    private let primary: KeyStore
    private let fallback: KeyStore

    public init(primary: KeyStore, fallback: KeyStore) {
        self.primary = primary
        self.fallback = fallback
    }

    /// 端末に合った既定の保存先
    public static func platformDefault() -> ResilientKeyStore {
        #if canImport(Security)
        return ResilientKeyStore(primary: KeychainKeyStore(), fallback: UserDefaultsKeyStore())
        #else
        return ResilientKeyStore(primary: InMemoryKeyStore(), fallback: UserDefaultsKeyStore())
        #endif
    }

    public func load(account: String) -> String? {
        primary.load(account: account) ?? fallback.load(account: account)
    }

    public func save(_ value: String, account: String) -> Bool {
        if primary.save(value, account: account) {
            fallback.delete(account: account)
            return true
        }
        return fallback.save(value, account: account)
    }

    public func delete(account: String) -> Bool {
        let first = primary.delete(account: account)
        let second = fallback.delete(account: account)
        return first && second
    }

    /// リージョンごとの保存名
    public static func account(for region: APIRegion) -> String { "apiKey.\(region.rawValue)" }
}
