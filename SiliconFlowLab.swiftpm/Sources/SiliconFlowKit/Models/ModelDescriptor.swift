import Foundation

/// 画面に表示する 1 モデル分の情報（API の一覧 + カタログ + Hugging Face を統合したもの）
public struct ModelDescriptor: Identifiable, Hashable, Sendable {
    public enum CategorySource: String, Sendable, Hashable {
        case api
        case catalog
        case heuristic
    }

    public var id: String
    public var category: ModelCategory
    public var categorySource: CategorySource
    /// あなたの API キーで `GET /models` に出てきたか
    public var isListedByAPI: Bool
    public var catalog: CatalogEntry?
    public var parameters: ParameterCount?
    public var parametersSource: String?

    public init(
        id: String,
        category: ModelCategory,
        categorySource: CategorySource,
        isListedByAPI: Bool,
        catalog: CatalogEntry?,
        parameters: ParameterCount?,
        parametersSource: String?
    ) {
        self.id = id
        self.category = category
        self.categorySource = categorySource
        self.isListedByAPI = isListedByAPI
        self.catalog = catalog
        self.parameters = parameters
        self.parametersSource = parametersSource
    }

    public var organization: String? { ModelClassifier.organization(of: id) }
    public var shortName: String { ModelClassifier.shortName(of: id) }
    public var displayName: String { catalog?.displayName ?? shortName }
    public var isPro: Bool { ModelClassifier.isProVariant(id) }
    public var isFree: Bool { catalog?.effectiveIsFree ?? false }
    public var isDeprecated: Bool { catalog?.deprecated ?? false }
    public var priceText: String { PriceFormatter.compact(catalog) }
    public var contextText: String { ContextLengthFormatter.format(catalog?.contextLength) }
    public var capabilities: [ModelCapability] { catalog?.capabilities ?? [] }

    public func has(_ capability: ModelCapability) -> Bool { capabilities.contains(capability) }

    /// 検索語（空白区切りの AND 検索、大文字小文字を区別しない）に一致するか
    public func matches(search text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
        guard !words.isEmpty else { return true }
        var haystack = id.lowercased() + " " + displayName.lowercased() + " " + category.displayName
        if let tags = catalog?.tags { haystack += " " + tags.joined(separator: " ").lowercased() }
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// ModelDescriptor の組み立て
public enum ModelDescriptorBuilder {
    /// - Parameters:
    ///   - remote: `GET /models` の結果
    ///   - apiCategories: sub_type 別の一覧から作った「モデル ID → カテゴリ」
    ///   - catalog: 価格などのカタログ
    ///   - hfParameters: Hugging Face から取得したパラメータ数
    public static func build(
        remote: [RemoteModel],
        apiCategories: [String: ModelCategory],
        catalog: CatalogIndex,
        hfParameters: [String: ParameterCount] = [:]
    ) -> [ModelDescriptor] {
        var seen = Set<String>()
        var result: [ModelDescriptor] = []
        result.reserveCapacity(remote.count)
        for model in remote where seen.insert(model.id).inserted {
            result.append(describe(model.id, isListed: true, apiCategory: apiCategories[model.id], catalog: catalog, hf: hfParameters[model.id]))
        }
        return result
    }

    /// API 一覧が取得できなかったとき用：カタログだけから一覧を作ります。
    public static func buildFromCatalog(_ catalog: CatalogIndex, hfParameters: [String: ParameterCount] = [:]) -> [ModelDescriptor] {
        catalog.allEntries
            .filter { !($0.deprecated ?? false) }
            .map { describe($0.id, isListed: false, apiCategory: nil, catalog: catalog, hf: hfParameters[$0.id]) }
            .sorted { $0.id < $1.id }
    }

    public static func describe(
        _ id: String,
        isListed: Bool,
        apiCategory: ModelCategory?,
        catalog: CatalogIndex,
        hf: ParameterCount?
    ) -> ModelDescriptor {
        let entry = catalog.lookup(id)
        let (category, source) = resolveCategory(id: id, apiCategory: apiCategory, entry: entry)
        let (parameters, parametersSource) = resolveParameters(id: id, entry: entry, hf: hf)
        return ModelDescriptor(
            id: id,
            category: category,
            categorySource: source,
            isListedByAPI: isListed,
            catalog: entry,
            parameters: parameters,
            parametersSource: parametersSource
        )
    }

    static func resolveCategory(id: String, apiCategory: ModelCategory?, entry: CatalogEntry?) -> (ModelCategory, ModelDescriptor.CategorySource) {
        let heuristic = ModelClassifier.heuristicCategory(for: id)
        let catalogSaysVision = entry?.category == .vision || (entry?.has(.vision) ?? false)
        if let apiCategory {
            if apiCategory == .chat, catalogSaysVision || heuristic == .vision {
                return (.vision, .api)
            }
            return (apiCategory, .api)
        }
        if let category = entry?.category {
            if category == .chat, catalogSaysVision { return (.vision, .catalog) }
            return (category, .catalog)
        }
        return (heuristic, .heuristic)
    }

    static func resolveParameters(id: String, entry: CatalogEntry?, hf: ParameterCount?) -> (ParameterCount?, String?) {
        var result = ParameterCount()
        var source: String?
        func add(_ candidate: ParameterCount?, _ name: String?) {
            guard let candidate, !candidate.isEmpty else { return }
            let before = result
            result = result.filling(from: candidate)
            if source == nil, result != before { source = name }
        }
        add(entry?.parameters, entry?.paramsSource ?? "カタログ")
        add(hf, HuggingFaceClient.sourceName)
        add(ParameterCountParser.parse(modelID: id), "モデル名から推定")
        add(KnownModelFacts.parameters(for: id), "公開情報")
        return result.isEmpty ? (nil, nil) : (result, source)
    }
}
