import XCTest
@testable import SiliconFlowKit

final class OfficialPricingScraperTests: XCTestCase {
    private func entries() throws -> [String: CatalogEntry] {
        let html = try Fixtures.data("siliconflow_cn_pricing_excerpt.html")
        let parsed = OfficialPricingScraper.parse(html: html, now: ISO8601.parse("2026-10-08T00:00:00Z")!)
        return Dictionary(uniqueKeysWithValues: parsed.map { ($0.id, $0) })
    }

    func testParsesModelsAcrossChunks() throws {
        let entries = try entries()
        XCTAssertEqual(entries.count, 7)
        XCTAssertNil(entries["broken"], "壊れた行は無視する")
    }

    func testChatModelWithVisionAndMoE() throws {
        let kimi = try XCTUnwrap(entries()["Pro/moonshotai/Kimi-K2.6"])
        XCTAssertEqual(kimi.displayName, "Kimi-K2.6 (Pro)")
        XCTAssertEqual(kimi.category, .vision)
        XCTAssertEqual(kimi.inputPrice, 6.5)
        XCTAssertEqual(kimi.outputPrice, 27)
        XCTAssertEqual(kimi.currency, .cny)
        XCTAssertEqual(kimi.unit, .perMillionTokens)
        XCTAssertEqual(kimi.totalParamsB, 1000)
        XCTAssertEqual(kimi.activeParamsB, 32, "説明文の「激活参数 32B」から")
        XCTAssertEqual(kimi.contextLength, 262_144)
        XCTAssertTrue(kimi.has(.vision))
        XCTAssertTrue(kimi.has(.tools))
        XCTAssertTrue(kimi.has(.reasoning))
        XCTAssertEqual(kimi.isFree, false)
        XCTAssertEqual(kimi.priceSource, OfficialPricingScraper.sourceName)
        XCTAssertEqual(kimi.releaseDate?.count, 10)
    }

    func testFreeModel() throws {
        let qwen = try XCTUnwrap(entries()["Qwen/Qwen3-8B"])
        XCTAssertEqual(qwen.isFree, true)
        XCTAssertTrue(qwen.effectiveIsFree)
        XCTAssertEqual(qwen.totalParamsB, 8)
        XCTAssertEqual(qwen.category, .chat)
    }

    func testNonTokenUnitsAndPreciseSizes() throws {
        let entries = try entries()
        let image = try XCTUnwrap(entries["Tongyi-MAI/Z-Image"])
        XCTAssertEqual(image.unit, .perImage)
        XCTAssertEqual(image.outputPrice, 0.3)
        XCTAssertNil(image.inputPrice)
        XCTAssertEqual(image.category, .textToImage)

        let tts = try XCTUnwrap(entries["FunAudioLLM/CosyVoice2-0.5B"])
        XCTAssertEqual(tts.totalParamsB, 0.5, "size は 1 に丸められているのでタグの 0.5B を使う")
        XCTAssertEqual(tts.unit, .perMillionBytes)
        XCTAssertNil(tts.displayName, "モデル ID と同じ表示名は持たない")

        let video = try XCTUnwrap(entries["Wan-AI/Wan2.2-T2V-A14B"])
        XCTAssertEqual(video.totalParamsB, 27)
        XCTAssertEqual(video.activeParamsB, 14)
        XCTAssertEqual(video.unit, .perVideo)
    }

    func testEmbeddingIsInputOnly() throws {
        let embedding = try XCTUnwrap(entries()["Qwen/Qwen3-Embedding-8B"])
        XCTAssertEqual(embedding.category, .embedding)
        XCTAssertNotNil(embedding.inputPrice)
        XCTAssertNil(embedding.outputPrice)
    }

    func testDeprecationDate() throws {
        let old = try XCTUnwrap(entries()["Qwen/Qwen2.5-14B-Instruct"])
        XCTAssertNotNil(old.deprecationDate)
        XCTAssertEqual(old.deprecated, true, "提供終了日を過ぎている")
    }

    func testGarbageInputReturnsEmpty() {
        XCTAssertTrue(OfficialPricingScraper.parse(html: Data("<html>no data</html>".utf8)).isEmpty)
        XCTAssertTrue(OfficialPricingScraper.parse(html: Data()).isEmpty)
        XCTAssertTrue(OfficialPricingScraper.parse(html: Data(#"<script>self.__next_f.push([1,"unterminated"#.utf8)).isEmpty)
    }
}

final class FlightDataReaderTests: XCTestCase {
    func testRowsReferencesAndTextRows() {
        let payload = "1:{\"tags\":\"$2\"}\n2:[\"a\",\"b\"]\n3:T5,ab\ncd4:{\"x\":1}\n"
        let literal = String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
        let html = "<script>self.__next_f.push([1,\(literal)])</script>"
        let reader = FlightDataReader(html: Data(html.utf8))
        XCTAssertEqual(reader.row("1")?["tags"], .string("$2"))
        XCTAssertEqual(reader.resolve(reader.row("1")?["tags"])?.arrayValue?.count, 2)
        XCTAssertEqual(reader.rawRow("3"), "ab\ncd", "T 行は長さ分そのまま読む")
        XCTAssertEqual(reader.row("4")?["x"]?.intValue, 1, "T 行の直後の行も読める")
        XCTAssertEqual(reader.rowIDs(containing: "\"x\""), ["4"])
        XCTAssertEqual(reader.resolve(.string("$zz")), .string("$zz"))
    }
}

final class ModelsDevCatalogTests: XCTestCase {
    func testSlicerFindsTopLevelKeyOnly() throws {
        let data = try Fixtures.data("models_dev_excerpt.json")
        let slice = try XCTUnwrap(JSONObjectSlicer.slice(topLevelKey: "siliconflow", in: data))
        let json = try XCTUnwrap(JSONValue.parse(slice))
        XCTAssertEqual(json["id"]?.stringValue, "siliconflow")
        XCTAssertNil(JSONObjectSlicer.slice(topLevelKey: "missing", in: data))
        XCTAssertNil(JSONObjectSlicer.slice(topLevelKey: "x", in: data), "入れ子のキーは対象外")
    }

    func testSlicerHandlesEscapesAndScalars() throws {
        let data = Data(#"{"a":"va\"l}","b":{"c":[1,{"d":"}"}]},"n":12}"#.utf8)
        XCTAssertEqual(String(decoding: try XCTUnwrap(JSONObjectSlicer.slice(topLevelKey: "b", in: data)), as: UTF8.self), #"{"c":[1,{"d":"}"}]}"#)
        XCTAssertEqual(String(decoding: try XCTUnwrap(JSONObjectSlicer.slice(topLevelKey: "a", in: data)), as: UTF8.self), #""va\"l}""#)
        XCTAssertEqual(String(decoding: try XCTUnwrap(JSONObjectSlicer.slice(topLevelKey: "n", in: data)), as: UTF8.self), "12")
    }

    func testParsesProvidersPerRegion() throws {
        let data = try Fixtures.data("models_dev_excerpt.json")
        let global = ModelsDevCatalog.parse(apiJSON: data, region: .international)
        XCTAssertEqual(global.map(\.id), ["Qwen/Qwen3-8B", "deepseek-ai/DeepSeek-V3.2", "nex-agi/Nex-N2-Pro"], "壊れたモデルは除外")
        let nex = try XCTUnwrap(global.last)
        XCTAssertEqual(nex.currency, .usd)
        XCTAssertEqual(nex.totalParamsB, 397)
        XCTAssertEqual(nex.activeParamsB, 17)
        XCTAssertEqual(nex.category, .vision)
        XCTAssertTrue(nex.has(.reasoning))
        XCTAssertEqual(nex.priceSource, ModelsDevCatalog.sourceName)
        XCTAssertNotNil(nex.contextLength)

        let cn = ModelsDevCatalog.parse(apiJSON: data, region: .china)
        XCTAssertEqual(cn.count, 3)
        XCTAssertEqual(cn.first { $0.id == "Qwen/Qwen3.5-4B" }?.effectiveIsFree, true)
        XCTAssertTrue(ModelsDevCatalog.parse(apiJSON: Data("{}".utf8), region: .china).isEmpty)
    }
}

final class CatalogMergeTests: XCTestCase {
    private func priced(_ id: String, _ input: Double, _ currency: Currency, source: String) -> CatalogEntry {
        var entry = CatalogEntry(id: id)
        entry.inputPrice = input
        entry.outputPrice = input * 2
        entry.currency = currency
        entry.unit = .perMillionTokens
        entry.priceSource = source
        return entry
    }

    func testMergerPrefersEarlierLayersPerField() {
        var official = priced("Qwen/Qwen3-8B", 1, .cny, source: "official")
        official.totalParamsB = 8
        var fallback = priced("qwen/qwen3-8b", 0.1, .usd, source: "models.dev")
        fallback.contextLength = 131_072
        fallback.capabilities = [.tools]
        let merged = CatalogMerger.merge([[official], [fallback, priced("other/model", 3, .usd, source: "x")]])
        XCTAssertEqual(merged.count, 2)
        let qwen = merged[0]
        XCTAssertEqual(qwen.inputPrice, 1)
        XCTAssertEqual(qwen.currency, .cny)
        XCTAssertEqual(qwen.priceSource, "official")
        XCTAssertEqual(qwen.contextLength, 131_072, "足りない項目は下位の情報源から補う")
        XCTAssertEqual(qwen.capabilities, [.tools])
    }

    func testPriceComesAsAWholeFromOneSource() {
        var noPrice = CatalogEntry(id: "a/b")
        noPrice.totalParamsB = 7
        let merged = noPrice.filling(from: priced("a/b", 2, .usd, source: "models.dev"))
        XCTAssertEqual(merged.inputPrice, 2)
        XCTAssertEqual(merged.currency, .usd)
        XCTAssertEqual(merged.priceSource, "models.dev")
        XCTAssertEqual(merged.totalParamsB, 7)
    }

    func testIndexFallsBackToBaseModelWithoutPrice() throws {
        var base = priced("deepseek-ai/DeepSeek-V3", 2, .cny, source: "official")
        base.contextLength = 65536
        base.totalParamsB = 671
        let index = CatalogIndex(entries: [base])
        let pro = try XCTUnwrap(index.lookup("Pro/deepseek-ai/DeepSeek-V3"))
        XCTAssertEqual(pro.id, "Pro/deepseek-ai/DeepSeek-V3")
        XCTAssertNil(pro.inputPrice, "Pro 版に通常版の価格は流用しない")
        XCTAssertEqual(pro.contextLength, 65536)
        XCTAssertEqual(pro.totalParamsB, 671)
        XCTAssertEqual(index.lookup("DEEPSEEK-AI/deepseek-v3")?.inputPrice, 2, "大文字小文字を区別しない")
        XCTAssertNil(index.lookup("unknown/model"))
    }

    func testDocumentRoundTrip() throws {
        let document = CatalogDocument(generatedAt: "2026-10-08T00:00:00Z", regions: ["cn": RegionCatalog(entries: [priced("a/b", 1, .cny, source: "s")])])
        let decoded = try CatalogDocument.decode(try document.encoded())
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.entries(for: .china).count, 1)
        XCTAssertTrue(decoded.entries(for: .international).isEmpty)
        XCTAssertNotNil(decoded.generatedDate)
        let encodedText = String(decoding: try document.encoded(pretty: false), as: UTF8.self)
        XCTAssertTrue(encodedText.contains("\"a/b\""), "スラッシュをエスケープしない")
    }

    func testBundledSnapshotIsValidAndUseful() throws {
        let document = try XCTUnwrap(BundledCatalog.document, "同梱カタログが壊れている")
        XCTAssertEqual(document.schemaVersion, CatalogDocument.currentSchemaVersion)
        for region in APIRegion.allCases {
            let entries = document.entries(for: region)
            XCTAssertGreaterThan(entries.count, 20, "\(region) の同梱データが少なすぎる")
            let priced = entries.filter(\.hasPrice)
            XCTAssertGreaterThan(Double(priced.count) / Double(entries.count), 0.8, "\(region) の価格情報が不足")
            XCTAssertTrue(entries.allSatisfy { $0.currency == nil || $0.currency == .cny || $0.currency == .usd })
        }
        XCTAssertTrue(document.entries(for: .china).contains { $0.currency == .cny }, "中国版は人民元価格を含む")
    }
}

final class HuggingFaceAndRatesTests: XCTestCase {
    func testCandidateRepoIDs() {
        XCTAssertEqual(HuggingFaceClient.candidateRepoIDs(for: "Pro/deepseek-ai/DeepSeek-V3"), ["deepseek-ai/DeepSeek-V3"])
        XCTAssertEqual(HuggingFaceClient.candidateRepoIDs(for: "Qwen/Qwen2.5-72B-Instruct-128K"), ["Qwen/Qwen2.5-72B-Instruct-128K", "Qwen/Qwen2.5-72B-Instruct"])
        XCTAssertTrue(HuggingFaceClient.candidateRepoIDs(for: "solo").isEmpty)
    }

    func testAPIURL() {
        let url = HuggingFaceClient.apiURL(for: "Qwen/Qwen3-8B")?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://huggingface.co/api/models/Qwen/Qwen3-8B?"))
        XCTAssertTrue(url.contains("expand%5B%5D=safetensors"))
    }

    func testParse() {
        let info = HuggingFaceClient.parse(Data(#"{"id":"Qwen/Qwen3-8B","pipeline_tag":"text-generation","cardData":{"license":"apache-2.0"},"downloads":10,"likes":2,"safetensors":{"parameters":{"BF16":8190735360},"total":8190735360}}"#.utf8))
        XCTAssertEqual(info?.totalParameters, 8_190_735_360)
        XCTAssertEqual(info?.parameters?.totalB, 8.19)
        XCTAssertEqual(info?.license, "apache-2.0")
        XCTAssertEqual(info?.pageURL?.absoluteString, "https://huggingface.co/Qwen/Qwen3-8B")
        let summed = HuggingFaceClient.parse(Data(#"{"id":"x/y","safetensors":{"parameters":{"BF16":1000000000,"F32":500000000}}}"#.utf8))
        XCTAssertEqual(summed?.totalParameters, 1_500_000_000)
        XCTAssertNil(HuggingFaceClient.parse(Data(#"{"error":"Repository not found"}"#.utf8)))
    }

    func testFetchUsesTransportAndToleratesFailures() async {
        let transport = MockTransport { request, _ in
            if request.url.path.contains("DeepSeek-V3") {
                return .json(#"{"id":"deepseek-ai/DeepSeek-V3","safetensors":{"total":684531386000}}"#)
            }
            return .json(#"{"error":"Repository not found"}"#, status: 404)
        }
        var fetcher = WebFetcher(transport: transport, retryPolicy: .none)
        fetcher.sleep = { _ in }
        let client = HuggingFaceClient(fetcher: fetcher)
        let found = await client.fetch(modelID: "Pro/deepseek-ai/DeepSeek-V3")
        XCTAssertEqual(found?.parameters?.totalB, 684.53)
        let missing = await client.fetch(modelID: "nobody/nothing")
        XCTAssertNil(missing)
    }

    func testExchangeRateParsing() throws {
        let erAPI = ExchangeRates.parse(Data(#"{"result":"success","base_code":"CNY","rates":{"CNY":1,"JPY":20.5,"USD":0.14}}"#.utf8), expectedBase: .cny, source: "t")
        XCTAssertEqual(erAPI?.rate(from: .cny, to: .jpy), 20.5)
        XCTAssertEqual(try XCTUnwrap(erAPI?.rate(from: .usd, to: .jpy)), 20.5 / 0.14, accuracy: 0.0001)
        let frankfurter = ExchangeRates.parse(Data(#"{"amount":1.0,"base":"USD","date":"2026-10-08","rates":{"JPY":148.2}}"#.utf8), expectedBase: .usd, source: "t")
        XCTAssertEqual(frankfurter?.rate(from: .usd, to: .jpy), 148.2)
        XCTAssertNil(ExchangeRates.parse(Data(#"{"result":"error"}"#.utf8), expectedBase: .cny, source: "t"))
        XCTAssertNil(ExchangeRates.parse(Data(#"{"base":"EUR","rates":{"JPY":1}}"#.utf8), expectedBase: .cny, source: "t"))
        let money = Money(amount: 2, currency: .cny).converted(to: .jpy, using: erAPI)
        XCTAssertEqual(money?.formatted, "41円")
        XCTAssertNil(Money(amount: 1, currency: .usd).converted(to: .jpy, using: nil))
        XCTAssertTrue(erAPI?.isFresh() ?? false)
    }

    func testExchangeRateClientFallsBack() async throws {
        let transport = MockTransport { request, _ in
            if request.url.host == "open.er-api.com" { return .failure(URLErrorStub.offline) }
            return .json(#"{"base":"CNY","rates":{"JPY":21}}"#)
        }
        var fetcher = WebFetcher(transport: transport, retryPolicy: .none)
        fetcher.sleep = { _ in }
        let rates = try await ExchangeRateClient(fetcher: fetcher).fetch(base: .cny)
        XCTAssertEqual(rates.rates["JPY"], 21)
        XCTAssertEqual(rates.source, "Frankfurter (ECB)")
    }
}

enum URLErrorStub {
    static var offline: Error { SiliconFlowError(kind: .offline) }
}
