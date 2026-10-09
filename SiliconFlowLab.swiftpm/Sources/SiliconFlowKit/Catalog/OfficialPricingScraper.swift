import Foundation

/// SiliconFlow 公式サイト（中国版）の料金ページから価格・パラメータ数を読み取ります。
///
/// ページの形式が変わっても例外は投げず、読めた分だけ返します
/// （0 件ならカタログの他の情報源にフォールバックします）。
public enum OfficialPricingScraper {
    public static let sourceName = "SiliconFlow公式サイト"
    public static let pageURL = URL(string: "https://siliconflow.cn/pricing")!

    public static func parse(html: Data, now: Date = Date()) -> [CatalogEntry] {
        let reader = FlightDataReader(html: html)
        var entries: [CatalogEntry] = []
        var seen = Set<String>()
        for rowID in reader.rowIDs(containing: "\"modelName\":\"") {
            guard let row = reader.row(rowID), let object = row.objectValue,
                  let entry = makeEntry(object, reader: reader, now: now),
                  !seen.contains(entry.id.lowercased())
            else { continue }
            seen.insert(entry.id.lowercased())
            entries.append(entry)
        }
        return entries
    }

    static func makeEntry(_ object: [String: JSONValue], reader: FlightDataReader, now: Date) -> CatalogEntry? {
        guard let name = object["modelName"]?.stringValue, !name.isEmpty, name.contains("/") else { return nil }
        var entry = CatalogEntry(id: name)
        if let display = nonEmpty(object["DisplayName"]?.stringValue), display != name, !display.contains("/") {
            entry.displayName = display
        }
        let tags = stringArray(reader.resolve(object["tags"]))
        entry.tags = tags.isEmpty ? nil : unique(tags)

        let isVLM = object["vlm"]?.boolValue ?? false
        if let subType = object["subType"]?.stringValue, let category = ModelCategory(apiSubType: subType) {
            entry.category = (category == .chat && isVLM) ? .vision : category
        }

        applyPrices(object, reader: reader, to: &entry)
        applyParameters(object, name: name, tags: tags, to: &entry)

        if let context = object["contextLen"]?.intValue, context > 0 { entry.contextLength = context }
        entry.capabilities = capabilities(object, tags: tags, isVLM: isVLM)
        entry.requiresChargedBalance = object["onlyByChargeBalance"]?.boolValue
        entry.requiresRealName = object["needAuth"]?.boolValue
        if let description = nonEmpty(object["desc"]?.stringValue) {
            entry.summary = TextSanitizer.snippet(description, limit: 280)
        }
        if let seconds = reader.resolve(object["publishTime"])?["seconds"]?.doubleValue, seconds > 0 {
            entry.releaseDate = dayString(Date(timeIntervalSince1970: seconds))
        }
        if let seconds = reader.resolve(object["deprecatedTime"])?["seconds"]?.doubleValue, seconds > 0 {
            let date = Date(timeIntervalSince1970: seconds)
            entry.deprecationDate = dayString(date)
            entry.deprecated = date <= now
        }
        if let status = object["status"]?.stringValue, !status.isEmpty, status != "normal" {
            entry.deprecated = true
        }
        return entry
    }

    private static func applyPrices(_ object: [String: JSONValue], reader: FlightDataReader, to entry: inout CatalogEntry) {
        entry.currency = Currency.from(symbol: object["currency"]?.stringValue) ?? .cny
        entry.unit = PriceUnit.parse(object["priceUnit"]?.stringValue ?? object["inputPriceUnit"]?.stringValue)

        var prompt: Double?
        var completion: Double?
        var single: Double?
        for item in (reader.resolve(object["pricing"])?.arrayValue ?? []) {
            guard let pricing = reader.resolve(item), let price = pricing["price"]?.doubleValue else { continue }
            switch pricing["specification"]?.stringValue?.lowercased() ?? "" {
            case "prompt", "input": prompt = price
            case "completion", "output": completion = price
            default: single = price
            }
            if entry.unit == .unknown || entry.unit == nil {
                entry.unit = PriceUnit.parse(pricing["unitOfGood"]?.stringValue)
            }
        }
        if prompt == nil, completion == nil, single == nil {
            completion = object["price"]?.doubleValue
            prompt = object["inputPrice"]?.doubleValue
        }

        if let single {
            entry.outputPrice = single
        } else {
            entry.inputPrice = prompt
            entry.outputPrice = completion
            // 埋め込み・リランクは入力だけに課金（出力 0）
            let inputOnly: Set<ModelCategory> = [.embedding, .reranker]
            if let category = entry.category, inputOnly.contains(category), (completion ?? 0) == 0, prompt != nil {
                entry.outputPrice = nil
            }
        }
        let tags = entry.tags ?? []
        let isZero = (entry.inputPrice ?? 0) == 0 && (entry.outputPrice ?? 0) == 0
        if entry.hasPrice {
            entry.isFree = isZero || tags.contains { $0.lowercased() == "free" }
            entry.priceSource = sourceName
        }
    }

    private static func applyParameters(_ object: [String: JSONValue], name: String, tags: [String], to entry: inout CatalogEntry) {
        var params = ParameterCount()
        // タグ（"0.5B" "753B" "1T"）が一番正確（size は整数に丸められている）
        for tag in tags {
            if let value = ParameterCountParser.parseSize(tag.trimmingCharacters(in: .whitespaces)) {
                params.totalB = value
                break
            }
        }
        let fromName = ParameterCountParser.parse(modelID: name)
        let fromDescription = ParameterCountParser.parse(description: object["desc"]?.stringValue)
        if params.totalB == nil, let nameTotal = fromName?.totalB {
            params.totalB = nameTotal
        }
        if params.totalB == nil, let size = object["size"]?.doubleValue, size > 0 {
            params.totalB = size
        }
        params = params.filling(from: fromDescription).filling(from: fromName)
        guard !params.isEmpty else { return }
        entry.totalParamsB = params.totalB
        entry.activeParamsB = params.activeB
        entry.paramsSource = sourceName
    }

    private static func capabilities(_ object: [String: JSONValue], tags: [String], isVLM: Bool) -> [ModelCapability]? {
        var result: [ModelCapability] = []
        if isVLM { result.append(.vision) }
        if object["functionCallSupport"]?.boolValue == true { result.append(.tools) }
        if object["jsonModeSupport"]?.boolValue == true { result.append(.jsonMode) }
        if object["fimCompletionSupport"]?.boolValue == true { result.append(.fim) }
        if object["chatPrefixCompletionSupport"]?.boolValue == true { result.append(.prefixCompletion) }
        let lowered = tags.map { $0.lowercased() }
        if lowered.contains(where: { $0.contains("推理") || $0.contains("reasoning") || $0.contains("thinking") }) {
            result.append(.reasoning)
        }
        return result.isEmpty ? nil : result
    }

    private static func stringArray(_ value: JSONValue?) -> [String] {
        (value?.arrayValue ?? []).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func dayString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
