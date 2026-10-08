import XCTest
@testable import SiliconFlowKit

final class CatalogServiceTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sfl-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func remoteCatalogJSON() throws -> String {
        var entry = CatalogEntry(id: "remote/only-model")
        entry.inputPrice = 1
        entry.outputPrice = 2
        entry.currency = .usd
        entry.unit = .perMillionTokens
        let document = CatalogDocument(generatedAt: "2026-10-01T00:00:00Z", regions: ["cn": RegionCatalog(entries: [entry]), "global": RegionCatalog(entries: [entry])])
        return String(decoding: try document.encoded(), as: UTF8.self)
    }

    private func service(_ handler: @escaping (HTTPRequest) -> MockTransport.Reply) -> (CatalogService, MockTransport) {
        let transport = MockTransport { request, _ in handler(request) }
        var fetcher = WebFetcher(transport: transport, retryPolicy: .none)
        fetcher.sleep = { _ in }
        let service = CatalogService(fetcher: fetcher, cache: DiskCache(directory: directory), remoteURLs: [URL(string: "https://example.com/catalog.json")!])
        return (service, transport)
    }

    func testCurrentFallsBackToBundled() async {
        let (service, transport) = service { _ in .failure(SiliconFlowError(kind: .offline)) }
        let snapshot = await service.current(region: .china)
        XCTAssertTrue(snapshot.isBundledOnly)
        XCTAssertFalse(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.isStale())
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRefreshChinaMergesOfficialRemoteAndBundled() async throws {
        let html = try Fixtures.data("siliconflow_cn_pricing_excerpt.html")
        let remote = try remoteCatalogJSON()
        let (service, transport) = service { request in
            switch request.url.host {
            case "siliconflow.cn": return MockTransport.Reply(status: 200, headers: ["Content-Type": "text/html"], body: html)
            case "example.com": return .json(remote)
            default: return .json("{}", status: 404)
            }
        }
        let snapshot = await service.refresh(region: .china)
        XCTAssertFalse(snapshot.isBundledOnly)
        XCTAssertNotNil(snapshot.updatedAt)
        let index = CatalogIndex(entries: snapshot.entries)
        XCTAssertEqual(index.lookup("Pro/moonshotai/Kimi-K2.6")?.priceSource, OfficialPricingScraper.sourceName)
        XCTAssertNotNil(index.lookup("remote/only-model"), "GitHub カタログの分も入る")
        XCTAssertNotNil(index.lookup("BAAI/bge-m3"), "同梱データの分も入る")
        XCTAssertEqual(snapshot.statuses.map(\.name), [OfficialPricingScraper.sourceName, RemoteCatalogClient.sourceName, BundledCatalog.sourceName])
        XCTAssertTrue(snapshot.statuses.allSatisfy(\.succeeded))
        XCTAssertFalse(transport.requests.contains { $0.url.host == "models.dev" }, "GitHub が使えたら models.dev は取らない")

        // ディスクキャッシュから復元できる
        let (second, secondTransport) = self.service { _ in .failure(SiliconFlowError(kind: .offline)) }
        let cached = await second.current(region: .china)
        XCTAssertFalse(cached.isBundledOnly)
        XCTAssertEqual(cached.entries.count, snapshot.entries.count)
        XCTAssertTrue(secondTransport.requests.isEmpty)
    }

    func testRefreshFallsBackToModelsDevWhenRemoteFails() async throws {
        let modelsDev = try Fixtures.data("models_dev_excerpt.json")
        let (service, _) = service { request in
            if request.url.host == "models.dev" { return MockTransport.Reply(status: 200, body: modelsDev) }
            return .text("<html>blocked</html>", status: 403, contentType: "text/html")
        }
        let snapshot = await service.refresh(region: .international)
        let names = snapshot.statuses.map(\.name)
        XCTAssertEqual(names, [RemoteCatalogClient.sourceName, ModelsDevCatalog.sourceName, BundledCatalog.sourceName], "国際版は公式サイトを取らない")
        XCTAssertFalse(snapshot.statuses[0].succeeded)
        XCTAssertNotNil(snapshot.statuses[0].message)
        XCTAssertTrue(snapshot.statuses[1].succeeded)
        XCTAssertEqual(CatalogIndex(entries: snapshot.entries).lookup("nex-agi/Nex-N2-Pro")?.currency, .usd)
    }

    func testRefreshWithEverythingOfflineKeepsBundled() async {
        let (service, _) = service { _ in .failure(SiliconFlowError(kind: .offline)) }
        let snapshot = await service.refresh(region: .china)
        XCTAssertTrue(snapshot.isBundledOnly)
        XCTAssertFalse(snapshot.entries.isEmpty, "オフラインでも同梱データで表示できる")
        XCTAssertTrue(snapshot.statuses.contains { !$0.succeeded })
    }

    func testDisabledSourcesAreNotFetched() async {
        let (service, transport) = service { _ in .json("{}") }
        _ = await service.refresh(region: .china, options: CatalogSourceOptions(useRemoteCatalog: false, useOfficialSite: false, useModelsDev: false))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testClearCache() async throws {
        let html = try Fixtures.data("siliconflow_cn_pricing_excerpt.html")
        let (service, _) = service { request in
            request.url.host == "siliconflow.cn" ? MockTransport.Reply(status: 200, body: html) : .json("{}", status: 500)
        }
        _ = await service.refresh(region: .china)
        await service.clearCache()
        let snapshot = await service.current(region: .china)
        XCTAssertTrue(snapshot.isBundledOnly)
    }
}

final class DiskCacheTests: XCTestCase {
    func testSaveLoadRemove() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sfl-cache-\(UUID().uuidString)")
        let cache = DiskCache(directory: directory)
        XCTAssertNil(cache.load([String].self, name: "x"))
        XCTAssertTrue(cache.save(["a", "b"], name: "x/y"))
        XCTAssertEqual(cache.load([String].self, name: "x/y"), ["a", "b"])
        XCTAssertTrue(cache.remove(name: "x/y"))
        XCTAssertNil(cache.load([String].self, name: "x/y"))
        XCTAssertTrue(cache.clear())
        XCTAssertFalse(DiskCache(directory: nil).save(1, name: "n"))
    }
}

final class KeyStoreTests: XCTestCase {
    func testInMemoryAndResilientStores() {
        let primary = InMemoryKeyStore()
        let fallback = InMemoryKeyStore()
        let store = ResilientKeyStore(primary: primary, fallback: fallback)
        let account = ResilientKeyStore.account(for: .china)
        XCTAssertEqual(account, "apiKey.cn")
        XCTAssertNil(store.load(account: account))
        XCTAssertTrue(store.save("sk-1", account: account))
        XCTAssertEqual(store.load(account: account), "sk-1")
        XCTAssertNil(fallback.load(account: account))
        XCTAssertTrue(store.delete(account: account))
        XCTAssertNil(store.load(account: account))
    }

    func testFallbackIsUsedWhenPrimaryFails() {
        final class FailingStore: KeyStore, @unchecked Sendable {
            func load(account: String) -> String? { nil }
            func save(_ value: String, account: String) -> Bool { false }
            func delete(account: String) -> Bool { true }
        }
        let fallback = InMemoryKeyStore()
        let store = ResilientKeyStore(primary: FailingStore(), fallback: fallback)
        XCTAssertTrue(store.save("sk-2", account: "a"))
        XCTAssertEqual(fallback.load(account: "a"), "sk-2")
        XCTAssertEqual(store.load(account: "a"), "sk-2")
    }

    func testUserDefaultsStore() throws {
        let suite = "sfl-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = UserDefaultsKeyStore(defaults: defaults)
        XCTAssertTrue(store.save("sk-3", account: "b"))
        XCTAssertEqual(store.load(account: "b"), "sk-3")
        XCTAssertTrue(store.delete(account: "b"))
        XCTAssertNil(store.load(account: "b"))
        defaults.removePersistentDomain(forName: suite)
    }
}

final class DiagnosticsTests: XCTestCase {
    func testAllStepsPass() async {
        let transport = MockTransport { request, _ in
            if request.header("Authorization") == nil { return .json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401) }
            switch request.url.path {
            case "/v1/user/info": return .json(#"{"code":20000,"data":{"id":"u","balance":"1.5","chargeBalance":"0","totalBalance":"1.5","status":"normal"}}"#)
            case "/v1/models": return .json(#"{"data":[{"id":"Qwen/Qwen3-8B"}]}"#)
            case "/v1/chat/completions": return .json(#"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#)
            default: return .json("{}", status: 404)
            }
        }
        let diagnostics = ConnectionDiagnostics(client: makeClient(transport))
        for step in DiagnosticStep.allCases {
            let outcome = await diagnostics.run(step, testModel: "Qwen/Qwen3-8B")
            guard case .passed(let message) = outcome else { return XCTFail("\(step): \(outcome)") }
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(step.title.isEmpty)
        }
        let chatBody = transport.requests.last { $0.url.path == "/v1/chat/completions" }?.body
        XCTAssertEqual(JSONValue.parse(chatBody ?? Data())?["max_tokens"]?.intValue, 16, "テスト送信は最小限のトークンで")
    }

    func testFailuresAreReported() async {
        let transport = MockTransport(.json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401))
        let diagnostics = ConnectionDiagnostics(client: makeClient(transport))
        let auth = await diagnostics.run(.authentication, testModel: nil)
        guard case .failed(let error) = auth else { return XCTFail("\(auth)") }
        XCTAssertEqual(error.kind, .invalidAPIKey)
        XCTAssertTrue(auth.isFailure)
        let skipped = await diagnostics.run(.testChat, testModel: nil)
        guard case .skipped = skipped else { return XCTFail("\(skipped)") }
        let format = await ConnectionDiagnostics(client: makeClient(transport, key: "")).run(.keyFormat, testModel: nil)
        XCTAssertTrue(format.isFailure)
        let warning = await ConnectionDiagnostics(client: makeClient(transport, key: "abcdefghijklmnopqrstuvwxyz")).run(.keyFormat, testModel: nil)
        guard case .warning = warning else { return XCTFail("\(warning)") }
    }

    func testZeroBalanceIsWarning() async {
        let transport = MockTransport(.json(#"{"data":{"id":"u","balance":"0","totalBalance":"0","status":"normal"}}"#))
        let outcome = await ConnectionDiagnostics(client: makeClient(transport)).run(.authentication, testModel: nil)
        guard case .warning(let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(message.contains("無料モデル"))
    }

    func testPreferredTestModel() {
        let catalog = CatalogIndex(entries: {
            var small = CatalogEntry(id: "Qwen/Qwen3-8B")
            small.inputPrice = 0
            small.outputPrice = 0
            small.totalParamsB = 8
            var tiny = CatalogEntry(id: "x/tiny-1B")
            tiny.inputPrice = 0
            tiny.outputPrice = 0
            return [small, tiny]
        }())
        let models = ModelDescriptorBuilder.build(remote: [RemoteModel(id: "Qwen/Qwen3-8B"), RemoteModel(id: "x/tiny-1B"), RemoteModel(id: "Pro/a/b")], apiCategories: [:], catalog: catalog)
        XCTAssertEqual(ConnectionDiagnostics.preferredTestModel(from: models), "x/tiny-1B")
        XCTAssertNil(ConnectionDiagnostics.preferredTestModel(from: []))
    }

    func testRegionDetectorFindsWorkingRegion() async {
        let transport = MockTransport { request, _ in
            if request.url.host == "api.siliconflow.com" {
                return .json(#"{"code":20000,"data":{"id":"global-user","totalBalance":"5"}}"#)
            }
            return .json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401)
        }
        let (result, errors) = await RegionDetector.detect(apiKey: "sk-abcdefghijklmnopqrstuvwxyz", preferred: .china, transport: transport)
        XCTAssertEqual(result?.region, .international)
        XCTAssertEqual(result?.userInfo.id, "global-user")
        XCTAssertEqual(errors[.china]?.kind, .invalidAPIKey)
    }

    func testRegionDetectorReportsBothFailures() async {
        let transport = MockTransport(.failure(SiliconFlowError(kind: .offline)))
        let (result, errors) = await RegionDetector.detect(apiKey: "sk-abcdefghijklmnopqrstuvwxyz", preferred: .international, transport: transport)
        XCTAssertNil(result)
        XCTAssertEqual(errors.count, 2)
    }
}

final class ChatSupportTests: XCTestCase {
    func testParametersBuildRequest() throws {
        var parameters = ChatParameters(systemPrompt: "  あなたは親切です  ", temperature: 5, maxTokens: 999_999, thinking: .on, thinkingBudget: 10, historyLimit: 2)
        let history = (0..<5).map { ChatMessagePayload(role: $0 % 2 == 0 ? .user : .assistant, text: "m\($0)") }
        let request = parameters.makeRequest(model: "m", history: history)
        XCTAssertEqual(request.messages.count, 2, "system + 直近 2 件（assistant 始まりは除く）")
        XCTAssertEqual(request.messages.last?.role, .user)
        XCTAssertEqual(request.messages.first?.role, .system)
        XCTAssertEqual(request.temperature, 2, "範囲内に収める")
        XCTAssertEqual(request.maxTokens, 32768)
        XCTAssertEqual(request.enableThinking, true)
        XCTAssertEqual(request.thinkingBudget, 128)
        parameters.thinking = .off
        XCTAssertEqual(parameters.makeRequest(model: "m", history: history).enableThinking, false)
        parameters.thinking = .automatic
        XCTAssertNil(parameters.makeRequest(model: "m", history: history).enableThinking)
        parameters.systemPrompt = ""
        XCTAssertEqual(parameters.makeRequest(model: "m", history: history).messages.first?.role, .user)
        let roundTrip = try JSONDecoder().decode(ChatParameters.self, from: JSONEncoder().encode(parameters))
        XCTAssertEqual(roundTrip, parameters)
    }

    func testTurnPayloads() {
        let text = ChatTurn(role: .user, content: "hi")
        XCTAssertEqual(text.payload, ChatMessagePayload(role: .user, text: "hi"))
        let image = ChatTurn(role: .user, content: "what?", imageDataURLs: ["data:image/jpeg;base64,AA"])
        XCTAssertEqual(image.payload?.content, .parts([.imageURL("data:image/jpeg;base64,AA", detail: .auto), .text("what?")]))
        var failed = ChatTurn(role: .assistant, content: "partial")
        failed.state = .failed
        XCTAssertNil(failed.payload)
        XCTAssertNil(ChatTurn(role: .assistant, content: "  ").payload)
        XCTAssertEqual(ChatTranscript.payloads(from: [text, failed, image]).count, 2)
        let markdown = ChatTranscript.markdown(turns: [text, ChatTurn(role: .assistant, content: "hello")], model: "Qwen/Qwen3-8B")
        XCTAssertTrue(markdown.contains("**あなた**"))
        XCTAssertTrue(markdown.contains("hello"))
    }

    func testCostEstimation() {
        var entry = CatalogEntry(id: "m")
        entry.inputPrice = 2
        entry.outputPrice = 8
        entry.currency = .cny
        entry.unit = .perMillionTokens
        let cost = CostEstimator.cost(usage: Usage(promptTokens: 1000, completionTokens: 500), entry: entry)
        XCTAssertEqual(cost?.amount ?? 0, 0.006, accuracy: 1e-12)
        XCTAssertEqual(cost?.currency, .cny)
        XCTAssertNil(CostEstimator.cost(usage: nil, entry: entry))
        XCTAssertNil(CostEstimator.cost(usage: Usage(promptTokens: 1), entry: CatalogEntry(id: "x")))
        XCTAssertEqual(CostEstimator.cost(inputTokens: 1_000_000, entry: entry)?.amount, 2)
        var free = entry
        free.inputPrice = 0
        free.outputPrice = 0
        XCTAssertEqual(CostEstimator.cost(usage: Usage(promptTokens: 10, completionTokens: 10), entry: free)?.amount, 0)
        var image = CatalogEntry(id: "img")
        image.outputPrice = 0.3
        image.unit = .perImage
        XCTAssertEqual(CostEstimator.cost(units: 2, entry: image)?.amount ?? 0, 0.6, accuracy: 1e-12)
        XCTAssertNil(CostEstimator.cost(units: 2, entry: entry))
        XCTAssertEqual((Money(amount: 1, currency: .cny) + Money(amount: 2, currency: .cny))?.amount, 3)
        XCTAssertNil(Money(amount: 1, currency: .cny) + Money(amount: 2, currency: .usd))
    }

    func testMarkdownBlocks() {
        let blocks = MarkdownBlockParser.parse("前置き\n```swift\nlet a = 1\n```\n後書き\n~~~\nraw\n")
        XCTAssertEqual(blocks, [
            .text("前置き"),
            .code(language: "swift", code: "let a = 1", isClosed: true),
            .text("後書き"),
            .code(language: nil, code: "raw\n", isClosed: false),
        ])
        XCTAssertEqual(MarkdownBlockParser.parse(""), [])
        XCTAssertEqual(MarkdownBlockParser.inlineFriendly("## 見出し\n- 項目\n  * 入れ子\n普通の文\n---"), "**見出し**\n• 項目\n  • 入れ子\n普通の文\n──────────")
        XCTAssertEqual(MarkdownBlockParser.inlineFriendly("#hashtag"), "**hashtag**")
        XCTAssertEqual(MarkdownBlockParser.inlineFriendly("2 * 3 = 6"), "2 * 3 = 6")
        XCTAssertEqual(MarkdownBlockParser.parse("```\n````"), [.code(language: nil, code: "", isClosed: true)])
    }

    func testVectorMath() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [1, 0]), 1)
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [0, 1]), 0)
        XCTAssertNil(VectorMath.cosineSimilarity([1], [1, 2]))
        XCTAssertNil(VectorMath.cosineSimilarity([0, 0], [0, 0]))
        XCTAssertEqual(VectorMath.norm([3, 4]), 5)
    }

    func testMultipartForm() {
        var form = MultipartFormData(boundary: "B")
        form.addField(name: "model", value: "m")
        form.addFile(name: "file", fileName: "a\"b.wav", mimeType: "audio/wav", data: Data("xyz".utf8))
        let body = String(decoding: form.finalized(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
        XCTAssertTrue(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nm\r\n"))
        XCTAssertTrue(body.contains("filename=\"a%22b.wav\""))
        XCTAssertTrue(body.hasSuffix("xyz\r\n--B--\r\n"))
        XCTAssertEqual(MultipartFormData.audioMimeType(forExtension: "MP3"), "audio/mpeg")
        XCTAssertEqual(MultipartFormData.audioMimeType(forExtension: "xyz"), "application/octet-stream")
    }

    func testJSONValueAccessors() {
        let json = JSONValue.parse(#"{"s":"6.5","n":2,"b":true,"a":[1],"o":{"k":"v"},"z":null}"#)
        XCTAssertEqual(json?["s"]?.doubleValue, 6.5)
        XCTAssertEqual(json?["n"]?.stringValue, "2")
        XCTAssertEqual(json?["n"]?.intValue, 2)
        XCTAssertEqual(json?["b"]?.boolValue, true)
        XCTAssertEqual(json?["a"]?.arrayValue?.count, 1)
        XCTAssertEqual(json?["o"]?["k"]?.stringValue, "v")
        XCTAssertTrue(json?["z"]?.isNull ?? false)
        XCTAssertNil(json?["missing"])
        XCTAssertEqual(JSONValue.string("yes").boolValue, true)
        XCTAssertNil(JSONValue.parse("not json"))
    }
}
