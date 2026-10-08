import Foundation
import SiliconFlowKit

/// モデル一覧・カタログ・残高・為替をまとめて管理します。
@MainActor
final class ModelStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(SiliconFlowError)
    }

    @Published private(set) var models: [ModelDescriptor] = []
    @Published private(set) var state: LoadState = .idle
    /// API の一覧が取れず、カタログだけで一覧を表示している
    @Published private(set) var isUsingCatalogFallback = false
    @Published private(set) var catalog: CatalogSnapshot
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var userInfo: UserInfo?
    @Published private(set) var balanceError: SiliconFlowError?
    @Published private(set) var isLoadingBalance = false
    @Published private(set) var exchangeRates: ExchangeRates?
    @Published private(set) var huggingFace: [String: HuggingFaceClient.ModelInfo] = [:]
    @Published private(set) var lastLoadedAt: Date?

    private var remoteModels: [RemoteModel] = []
    private var apiCategories: [String: ModelCategory] = [:]
    private var catalogIndex: CatalogIndex
    private var loadedRegion: APIRegion?
    private var loadTask: Task<Void, Never>?
    private var huggingFaceInFlight = Set<String>()
    private let catalogService = CatalogService()
    private let cache = DiskCache.default()

    init() {
        let initial = CatalogSnapshot(region: .china, entries: BundledCatalog.document?.entries(for: .china) ?? [], statuses: [], updatedAt: nil, isBundledOnly: true)
        catalog = initial
        catalogIndex = CatalogIndex(entries: initial.entries)
        huggingFace = cache.load([String: HuggingFaceClient.ModelInfo].self, name: "huggingface") ?? [:]
        exchangeRates = cache.load(ExchangeRates.self, name: "exchange-rates")
    }

    var isLoading: Bool { state == .loading }

    var loadError: SiliconFlowError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    func model(id: String?) -> ModelDescriptor? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    // MARK: - 読み込み

    /// モデル一覧・残高・カタログを読み直します（前回の読み込みは中止）。
    func reload(settings: AppSettings) {
        loadTask?.cancel()
        let client = settings.makeClient()
        let region = settings.region
        let options = settings.catalogOptions
        let wantsYen = settings.showYen
        state = .loading
        loadTask = Task { [weak self] in
            await self?.performLoad(client: client, region: region, options: options, wantsYen: wantsYen)
        }
    }

    private func performLoad(client: SiliconFlowClient, region: APIRegion, options: CatalogSourceOptions, wantsYen: Bool) async {
        if loadedRegion != region {
            loadedRegion = region
            remoteModels = []
            apiCategories = [:]
            userInfo = nil
        }
        apply(await catalogService.current(region: region))
        async let modelsResult = Self.fetchModels(client)
        async let balanceTask: Void = refreshBalance(client: client)
        let result = await modelsResult
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let fetched):
            remoteModels = fetched.models
            apiCategories = fetched.categories
            isUsingCatalogFallback = false
            state = .loaded
            lastLoadedAt = Date()
        case .failure(let error):
            if error.isCancellation { return }
            isUsingCatalogFallback = remoteModels.isEmpty
            state = .failed(error)
        }
        rebuild()
        await balanceTask
        if catalog.isStale() { await refreshCatalog(region: region, options: options) }
        // レートは基準通貨経由で相互換算できるので、新しさだけを見ます
        let ratesAreFresh = exchangeRates?.isFresh() ?? false
        if wantsYen, !ratesAreFresh {
            await refreshRates(base: region.currency)
        }
    }

    /// カタログを Web から取り直します。
    func refreshCatalog(region: APIRegion, options: CatalogSourceOptions) async {
        guard !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        let snapshot = await catalogService.refresh(region: region, options: options)
        isRefreshingCatalog = false
        guard region == (loadedRegion ?? region) else { return }
        apply(snapshot)
        rebuild()
    }

    func clearCaches() async {
        await catalogService.clearCache()
        cache.clear()
        huggingFace = [:]
        exchangeRates = nil
        if let region = loadedRegion { apply(await catalogService.current(region: region)) }
        rebuild()
    }

    func refreshBalance(client: SiliconFlowClient) async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        do {
            userInfo = try await client.userInfo()
            balanceError = nil
        } catch {
            let wrapped = SiliconFlowError.wrap(error, region: client.region)
            if !wrapped.isCancellation { balanceError = wrapped }
        }
    }

    func refreshRates(base: Currency) async {
        do {
            let rates = try await ExchangeRateClient().fetch(base: base)
            exchangeRates = rates
            cache.save(rates, name: "exchange-rates")
        } catch {
            // 為替は補助情報なので、失敗しても表示を省くだけにします
        }
    }

    /// Hugging Face から実際のパラメータ数などを取得します（未取得のモデルだけ）。
    func fetchHuggingFaceIfNeeded(for modelID: String, enabled: Bool) async {
        guard enabled, huggingFace[modelID] == nil, !huggingFaceInFlight.contains(modelID) else { return }
        huggingFaceInFlight.insert(modelID)
        defer { huggingFaceInFlight.remove(modelID) }
        guard let info = await HuggingFaceClient().fetch(modelID: modelID) else { return }
        huggingFace[modelID] = info
        cache.save(huggingFace, name: "huggingface")
        rebuild()
    }

    // MARK: - 内部処理

    private func apply(_ snapshot: CatalogSnapshot) {
        catalog = snapshot
        catalogIndex = CatalogIndex(entries: snapshot.entries)
    }

    private func rebuild() {
        var parameters: [String: ParameterCount] = [:]
        for (id, info) in huggingFace {
            if let count = info.parameters { parameters[id] = count }
        }
        if remoteModels.isEmpty {
            models = isUsingCatalogFallback ? ModelDescriptorBuilder.buildFromCatalog(catalogIndex, hfParameters: parameters) : []
        } else {
            models = ModelDescriptorBuilder.build(remote: remoteModels, apiCategories: apiCategories, catalog: catalogIndex, hfParameters: parameters)
        }
    }

    struct FetchedModels: Sendable {
        var models: [RemoteModel]
        var categories: [String: ModelCategory]
    }

    /// 全モデル + 種類別の一覧を並行して取得し、カテゴリを判定します。
    nonisolated static func fetchModels(_ client: SiliconFlowClient) async -> Result<FetchedModels, SiliconFlowError> {
        do {
            let all = try await client.listModels(.all)
            var bySubType: [String: ModelCategory] = [:]
            var byType: [String: ModelCategory] = [:]
            await withTaskGroup(of: (ModelListFilter, [RemoteModel]?).self) { group in
                for filter in ModelListFilter.classificationFilters {
                    group.addTask { (filter, try? await client.listModels(filter)) }
                }
                for await (filter, models) in group {
                    guard let models else { continue }
                    switch filter {
                    case .subType(let value):
                        guard let category = ModelCategory(apiSubType: value) else { continue }
                        for model in models { bySubType[model.id] = category }
                    case .type(let value):
                        let category: ModelCategory = value == "audio" ? .textToSpeech : .imageToVideo
                        for model in models { byType[model.id] = category }
                    case .all:
                        continue
                    }
                }
            }
            var categories = byType
            for (id, category) in bySubType { categories[id] = category }
            return .success(FetchedModels(models: all, categories: categories))
        } catch {
            return .failure(SiliconFlowError.wrap(error, region: client.region))
        }
    }
}
