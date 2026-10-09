import Foundation
import SiliconFlowKit

/// アプリの設定（UserDefaults とキーチェーンに保存）
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let region = "settings.region"
        static let customBaseURLEnabled = "settings.customBaseURLEnabled"
        static let customBaseURLText = "settings.customBaseURLText"
        static let requestTimeout = "settings.requestTimeout"
        static let catalogOptions = "settings.catalogOptions"
        static let useHuggingFace = "settings.useHuggingFace"
        static let showYen = "settings.showYen"
        static let chatParameters = "settings.chatParameters"
    }

    private let defaults: UserDefaults
    private let keyStore: KeyStore

    @Published var region: APIRegion {
        didSet {
            defaults.set(region.rawValue, forKey: Keys.region)
            connectionRevision += 1
        }
    }

    @Published var customBaseURLEnabled: Bool {
        didSet {
            defaults.set(customBaseURLEnabled, forKey: Keys.customBaseURLEnabled)
            connectionRevision += 1
        }
    }

    @Published var customBaseURLText: String {
        didSet { defaults.set(customBaseURLText, forKey: Keys.customBaseURLText) }
    }

    @Published var requestTimeout: Double {
        didSet { defaults.set(requestTimeout, forKey: Keys.requestTimeout) }
    }

    @Published var catalogOptions: CatalogSourceOptions {
        didSet { saveJSON(catalogOptions, key: Keys.catalogOptions) }
    }

    @Published var useHuggingFace: Bool {
        didSet { defaults.set(useHuggingFace, forKey: Keys.useHuggingFace) }
    }

    @Published var showYen: Bool {
        didSet { defaults.set(showYen, forKey: Keys.showYen) }
    }

    @Published var chatParameters: ChatParameters {
        didSet { saveJSON(chatParameters, key: Keys.chatParameters) }
    }

    /// API キーが保存されているリージョン
    @Published private(set) var regionsWithKey: Set<APIRegion> = []

    /// 接続先（リージョン・キー・URL）が変わるたびに増える番号。モデル一覧の再読み込みに使います。
    @Published private(set) var connectionRevision = 0

    init(defaults: UserDefaults = .standard, keyStore: KeyStore = ResilientKeyStore.platformDefault()) {
        self.defaults = defaults
        self.keyStore = keyStore
        region = APIRegion(rawValue: defaults.string(forKey: Keys.region) ?? "") ?? .china
        customBaseURLEnabled = defaults.bool(forKey: Keys.customBaseURLEnabled)
        customBaseURLText = defaults.string(forKey: Keys.customBaseURLText) ?? ""
        let timeout = defaults.double(forKey: Keys.requestTimeout)
        requestTimeout = timeout >= 10 ? timeout : 120
        catalogOptions = Self.loadJSON(CatalogSourceOptions.self, defaults: defaults, key: Keys.catalogOptions) ?? CatalogSourceOptions()
        useHuggingFace = defaults.object(forKey: Keys.useHuggingFace) as? Bool ?? true
        showYen = defaults.object(forKey: Keys.showYen) as? Bool ?? true
        chatParameters = Self.loadJSON(ChatParameters.self, defaults: defaults, key: Keys.chatParameters) ?? .default
        refreshStoredKeys()
    }

    // MARK: - API キー

    func apiKey(for region: APIRegion) -> String? {
        guard let key = keyStore.load(account: ResilientKeyStore.account(for: region)), !key.isEmpty else { return nil }
        return key
    }

    var currentAPIKey: String? { apiKey(for: region) }
    var hasKeyForCurrentRegion: Bool { regionsWithKey.contains(region) }
    var hasAnyKey: Bool { !regionsWithKey.isEmpty }

    @discardableResult
    func saveAPIKey(_ rawKey: String, for region: APIRegion) -> Bool {
        let key = APIKeyValidator.sanitize(rawKey)
        guard !key.isEmpty else { return false }
        let saved = keyStore.save(key, account: ResilientKeyStore.account(for: region))
        refreshStoredKeys()
        if region == self.region { connectionRevision += 1 }
        return saved
    }

    func deleteAPIKey(for region: APIRegion) {
        keyStore.delete(account: ResilientKeyStore.account(for: region))
        refreshStoredKeys()
        if region == self.region { connectionRevision += 1 }
    }

    private func refreshStoredKeys() {
        regionsWithKey = Set(APIRegion.allCases.filter { apiKey(for: $0) != nil })
    }

    // MARK: - 接続

    /// 有効なカスタム URL（無効・未設定なら nil）
    var customBaseURL: URL? {
        guard customBaseURLEnabled, case .success(let url) = BaseURLNormalizer.normalize(customBaseURLText) else { return nil }
        return url
    }

    func applyCustomBaseURL() {
        connectionRevision += 1
    }

    func makeClient(region overrideRegion: APIRegion? = nil) -> SiliconFlowClient {
        let target = overrideRegion ?? region
        let configuration = ClientConfiguration(
            region: target,
            apiKey: apiKey(for: target) ?? "",
            customBaseURL: overrideRegion == nil ? customBaseURL : nil,
            requestTimeout: requestTimeout
        )
        return SiliconFlowClient(configuration: configuration)
    }

    func resetChatParameters() {
        chatParameters = .default
    }

    // MARK: - 保存

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
