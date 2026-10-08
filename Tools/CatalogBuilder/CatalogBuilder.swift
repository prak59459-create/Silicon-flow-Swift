import Foundation
import SiliconFlowKit

/// Web から SiliconFlow のモデル価格・パラメータ数を集めてカタログを作るツール。
///
/// GitHub Actions（.github/workflows/catalog.yml）が毎日実行し、
/// `catalog/siliconflow-catalog.json`（アプリが起動時に取得）と
/// アプリ同梱のオフライン用データを更新します。
///
///     swift run catalog-builder --out catalog/siliconflow-catalog.json \
///         --swift-out SiliconFlowLab.swiftpm/Sources/SiliconFlowKit/Catalog/BundledCatalogSnapshot.swift
@main
struct CatalogBuilder {
    struct Options {
        var out = "catalog/siliconflow-catalog.json"
        var swiftOut: String?
        var huggingFaceLimit = 120
    }

    static func main() async {
        let options = parseArguments(Array(CommandLine.arguments.dropFirst()))
        let fetcher = WebFetcher(retryPolicy: RetryPolicy(maxRetries: 3), timeout: 60, maxBytes: 64 * 1024 * 1024)
        var notes: [String] = []

        // 1. 公式サイト（中国版の人民元価格）
        var official: [CatalogEntry] = []
        do {
            let html = try await fetcher.get(OfficialPricingScraper.pageURL, accept: "text/html")
            official = OfficialPricingScraper.parse(html: html)
            notes.append("\(OfficialPricingScraper.sourceName): \(official.count) models")
        } catch {
            notes.append("\(OfficialPricingScraper.sourceName): failed (\(SiliconFlowError.wrap(error).diagnosis.title))")
        }

        // 2. models.dev（両リージョンの米ドル価格・仕様）
        var modelsDevCN: [CatalogEntry] = []
        var modelsDevGlobal: [CatalogEntry] = []
        do {
            let data = try await fetcher.get(ModelsDevCatalog.apiURL, accept: "application/json")
            modelsDevCN = ModelsDevCatalog.parse(apiJSON: data, region: .china)
            modelsDevGlobal = ModelsDevCatalog.parse(apiJSON: data, region: .international)
            notes.append("\(ModelsDevCatalog.sourceName): cn \(modelsDevCN.count) / global \(modelsDevGlobal.count) models")
        } catch {
            notes.append("\(ModelsDevCatalog.sourceName): failed (\(SiliconFlowError.wrap(error).diagnosis.title))")
        }

        guard !official.isEmpty || !modelsDevGlobal.isEmpty else {
            log("ERROR: すべての情報源から取得できませんでした")
            notes.forEach { log("  " + $0) }
            exit(1)
        }

        // 前回のカタログは、取得に失敗した情報源があるときだけ予備として使う
        // （毎回混ぜると、公式サイトから消えたモデルや古い値がいつまでも残るため）
        let previous = loadPrevious(options.out)
        var cnLayers = [official, modelsDevCN]
        if official.isEmpty || modelsDevCN.isEmpty { cnLayers.append(previous?.entries(for: .china) ?? []) }
        var globalLayers = [modelsDevGlobal]
        if modelsDevGlobal.isEmpty { globalLayers.append(previous?.entries(for: .international) ?? []) }
        var cn = CatalogMerger.merge(cnLayers)
        var global = CatalogMerger.merge(globalLayers)

        // 3. Hugging Face でパラメータ数を補完
        let enrichment = await huggingFaceParameters(for: cn + global, limit: options.huggingFaceLimit)
        notes.append("\(HuggingFaceClient.sourceName): \(enrichment.count) models enriched")
        cn = apply(enrichment, to: cn)
        global = apply(enrichment, to: global)

        let regions = [
            APIRegion.china.rawValue: RegionCatalog(entries: cn.sorted { $0.id < $1.id }),
            APIRegion.international.rawValue: RegionCatalog(entries: global.sorted { $0.id < $1.id }),
        ]
        // 内容が変わっていなければ作成日時も据え置き（無駄なコミットを作らない）
        let unchanged = previous?.regions == regions
        let generatedAt = unchanged ? (previous?.generatedAt ?? ISO8601.string(from: Date())) : ISO8601.string(from: Date())
        let document = CatalogDocument(generatedAt: generatedAt, regions: regions, sources: unchanged ? previous?.sources : notes)

        do {
            try write(document.encoded(pretty: true), to: options.out)
            log("wrote \(options.out) (cn \(cn.count), global \(global.count))\(unchanged ? " [unchanged]" : "")")
            if let swiftOut = options.swiftOut {
                try writeSwiftSnapshot(document, to: swiftOut)
                log("wrote \(swiftOut)")
            }
        } catch {
            log("ERROR: 書き込みに失敗しました: \(error)")
            exit(1)
        }
        notes.forEach { log("  " + $0) }
    }

    // MARK: - Hugging Face

    static func huggingFaceParameters(for entries: [CatalogEntry], limit: Int) async -> [String: ParameterCount] {
        let targets = entries
            .filter { $0.totalParamsB == nil && ParameterCountParser.parse(modelID: $0.id)?.totalB == nil }
            .map { ModelClassifier.strippedPrefixes($0.id) }
        let unique = Array(Set(targets)).sorted().prefix(limit)
        guard !unique.isEmpty else { return [:] }
        let client = HuggingFaceClient()
        var result: [String: ParameterCount] = [:]
        await withTaskGroup(of: (String, ParameterCount?).self) { group in
            var iterator = unique.makeIterator()
            for _ in 0..<4 {
                guard let id = iterator.next() else { break }
                group.addTask { (id, await client.fetch(modelID: id)?.parameters) }
            }
            while let (id, parameters) = await group.next() {
                if let parameters { result[id.lowercased()] = parameters }
                if let next = iterator.next() {
                    group.addTask { (next, await client.fetch(modelID: next)?.parameters) }
                }
            }
        }
        return result
    }

    static func apply(_ parameters: [String: ParameterCount], to entries: [CatalogEntry]) -> [CatalogEntry] {
        entries.map { entry in
            guard entry.totalParamsB == nil, let found = parameters[ModelClassifier.strippedPrefixes(entry.id).lowercased()] else { return entry }
            var copy = entry
            copy.totalParamsB = found.totalB
            copy.paramsSource = copy.paramsSource ?? HuggingFaceClient.sourceName
            return copy
        }
    }

    // MARK: - 入出力

    static func parseArguments(_ arguments: [String]) -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--out": if let value = iterator.next() { options.out = value }
            case "--swift-out": options.swiftOut = iterator.next()
            case "--hf-limit": if let value = iterator.next().flatMap(Int.init) { options.huggingFaceLimit = value }
            default: log("unknown argument: \(argument)")
            }
        }
        return options
    }

    static func loadPrevious(_ path: String) -> CatalogDocument? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? CatalogDocument.decode(data)
    }

    static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output = data
        output.append(0x0A)
        try output.write(to: url, options: .atomic)
    }

    /// アプリ同梱用：説明文などを省いて小さくした JSON を Swift の文字列リテラルにします。
    static func writeSwiftSnapshot(_ document: CatalogDocument, to path: String) throws {
        var slim = document
        slim.sources = nil
        for (key, region) in slim.regions {
            slim.regions[key] = RegionCatalog(entries: region.entries.map(slimmed))
        }
        let json = String(decoding: try slim.encoded(pretty: false), as: UTF8.self)
        guard !json.contains("\"\"\"#") else { throw CocoaError(.fileWriteInvalidFileName) }
        // 1 行が長すぎるとエディタが重くなるので、モデルごとに改行します
        let wrapped = json.replacingOccurrences(of: "},{\"", with: "},\n{\"")
        let source = """
        // このファイルは `swift run catalog-builder` で自動生成されます。手で編集しないでください。
        // オフライン時・Web から取得できないときに使う価格・パラメータ数のデータです。
        enum BundledCatalogSnapshot {
            static let json = #\"\"\"
        \(wrapped)
        \"\"\"#
        }

        """
        try write(Data(source.utf8).dropLast(), to: path)
    }

    static func slimmed(_ entry: CatalogEntry) -> CatalogEntry {
        var copy = entry
        copy.summary = nil
        copy.tags = nil
        copy.releaseDate = copy.releaseDate.map { String($0.prefix(10)) }
        return copy
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
