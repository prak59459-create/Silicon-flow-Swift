import Foundation

/// models.dev（オープンなモデル情報データベース）から SiliconFlow の価格・仕様を読み取ります。
///
/// 価格は米ドル（100万トークンあたり）です。
public enum ModelsDevCatalog {
    public static let sourceName = "models.dev"
    public static let apiURL = URL(string: "https://models.dev/api.json")!

    /// リージョンに対応する models.dev のプロバイダ名
    public static func providerKey(for region: APIRegion) -> String {
        switch region {
        case .china: return "siliconflow-cn"
        case .international: return "siliconflow"
        }
    }

    /// api.json 全体から、指定プロバイダのモデルだけを読みます。
    public static func parse(apiJSON data: Data, region: APIRegion) -> [CatalogEntry] {
        guard let slice = JSONObjectSlicer.slice(topLevelKey: providerKey(for: region), in: data) else { return [] }
        return parse(providerJSON: slice)
    }

    /// プロバイダ部分（`{"id":"siliconflow","models":{...}}`）を読みます。
    public static func parse(providerJSON data: Data) -> [CatalogEntry] {
        guard let provider = try? JSONDecoder().decode(Provider.self, from: data) else { return [] }
        return provider.models.values
            .compactMap { $0.value?.entry }
            .sorted { $0.id < $1.id }
    }

    struct Provider: Decodable {
        let models: [String: FailableDecodable<Model>]
    }

    struct Model: Decodable {
        struct Cost: Decodable {
            let input: Double?
            let output: Double?
        }

        struct Limit: Decodable {
            let context: Int?
            let output: Int?
        }

        struct Modalities: Decodable {
            let input: [String]?
            let output: [String]?
        }

        let id: String
        let name: String?
        let description: String?
        let reasoning: Bool?
        let toolCall: Bool?
        let structuredOutput: Bool?
        let attachment: Bool?
        let releaseDate: String?
        let modalities: Modalities?
        let limit: Limit?
        let cost: Cost?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case description
            case reasoning
            case toolCall = "tool_call"
            case structuredOutput = "structured_output"
            case attachment
            case releaseDate = "release_date"
            case modalities
            case limit
            case cost
        }

        var entry: CatalogEntry {
            var entry = CatalogEntry(id: id)
            if let name, name != id, !name.contains("/") { entry.displayName = name }
            if let cost, cost.input != nil || cost.output != nil {
                entry.inputPrice = cost.input
                entry.outputPrice = cost.output
                entry.currency = .usd
                entry.unit = .perMillionTokens
                entry.isFree = (cost.input ?? 0) == 0 && (cost.output ?? 0) == 0
                entry.priceSource = ModelsDevCatalog.sourceName
            }
            if let context = limit?.context, context > 0 { entry.contextLength = context }
            if let output = limit?.output, output > 0 { entry.maxOutputTokens = output }
            entry.capabilities = capabilities
            entry.category = category
            entry.releaseDate = releaseDate
            if let description, !description.isEmpty {
                entry.summary = TextSanitizer.snippet(description, limit: 200)
            }
            let params = (ParameterCountParser.parse(description: description) ?? ParameterCount())
                .filling(from: ParameterCountParser.parse(modelID: id))
            if !params.isEmpty {
                entry.totalParamsB = params.totalB
                entry.activeParamsB = params.activeB
                entry.paramsSource = ModelsDevCatalog.sourceName
            }
            return entry
        }

        var capabilities: [ModelCapability]? {
            var result: [ModelCapability] = []
            let inputs = modalities?.input ?? []
            if inputs.contains("image") { result.append(.vision) }
            if inputs.contains("video") { result.append(.videoInput) }
            if inputs.contains("audio") { result.append(.audioInput) }
            if toolCall == true { result.append(.tools) }
            if structuredOutput == true { result.append(.jsonMode) }
            if reasoning == true { result.append(.reasoning) }
            return result.isEmpty ? nil : result
        }

        var category: ModelCategory? {
            let outputs = modalities?.output ?? []
            let inputs = modalities?.input ?? []
            if outputs.contains("image") { return inputs.contains("image") ? .imageToImage : .textToImage }
            if outputs.contains("video") { return .textToVideo }
            if outputs.contains("audio") && !outputs.contains("text") { return .textToSpeech }
            if outputs.contains("text") { return inputs.contains("image") ? .vision : .chat }
            return nil
        }
    }
}
