import XCTest
@testable import SiliconFlowKit

/// 本物の API・Web を使う結合テスト。
///
/// - `SILICONFLOW_API_KEY`（と任意で `SILICONFLOW_REGION` = cn / global）があるときだけ API を呼びます。
///   GitHub Actions ではリポジトリの Secrets に登録すると実行されます。
/// - `LIVE_WEB_TESTS=1` のときだけ公式サイト・models.dev・Hugging Face から実際に取得します。
final class LiveAPITests: XCTestCase {
    private func liveClient() throws -> SiliconFlowClient {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["SILICONFLOW_API_KEY"], !key.isEmpty else {
            throw XCTSkip("SILICONFLOW_API_KEY が無いので本番 API のテストは省略します")
        }
        let region = APIRegion(rawValue: environment["SILICONFLOW_REGION"] ?? "") ?? .china
        return SiliconFlowClient(configuration: ClientConfiguration(region: region, apiKey: key, requestTimeout: 60))
    }

    func testLiveUserInfoAndModels() async throws {
        let client = try liveClient()
        let info = try await client.userInfo()
        XCTAssertNotNil(info.id)
        let models = try await client.listModels()
        XCTAssertFalse(models.isEmpty)
        let chat = try await client.listModels(.subType("chat"))
        XCTAssertFalse(chat.isEmpty)
    }

    func testLiveStreamingChatWithFreeModel() async throws {
        let client = try liveClient()
        let models = try await client.listModels(.subType("chat"))
        let candidates = ["Qwen/Qwen3-8B", "Qwen/Qwen2.5-7B-Instruct", "THUDM/GLM-4-9B-0414"]
        guard let model = candidates.first(where: { id in models.contains { $0.id == id } }) else {
            throw XCTSkip("無料のテスト用モデルが見つかりません")
        }
        let request = ChatCompletionRequest(model: model, messages: [ChatMessagePayload(role: .user, text: "Say OK")], maxTokens: 32, enableThinking: model.hasPrefix("Qwen/Qwen3") ? false : nil)
        var accumulator = GenerationAccumulator(startedAt: 0)
        for try await chunk in client.streamChat(request) { accumulator.apply(chunk, at: 1) }
        XCTAssertFalse(accumulator.content.isEmpty && accumulator.reasoning.isEmpty)
    }

    func testLiveInvalidKeyIsDiagnosed() async throws {
        _ = try liveClient()
        let client = SiliconFlowClient(configuration: ClientConfiguration(region: .china, apiKey: "sk-invalidinvalidinvalidinvalid"))
        let error = await assertThrowsSiliconFlowError { try await client.userInfo() }
        XCTAssertEqual(error?.kind, .invalidAPIKey)
    }
}

final class LiveWebSourceTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["LIVE_WEB_TESTS"] == "1" else {
            throw XCTSkip("LIVE_WEB_TESTS=1 のときだけ実行します")
        }
    }

    func testOfficialPricingPageStillParses() async throws {
        let html = try await WebFetcher(timeout: 60).get(OfficialPricingScraper.pageURL, accept: "text/html")
        let entries = OfficialPricingScraper.parse(html: html)
        XCTAssertGreaterThan(entries.count, 20, "公式サイトの形式が変わった可能性があります")
        XCTAssertGreaterThan(entries.filter(\.hasPrice).count, 20)
    }

    func testModelsDevStillParses() async throws {
        let data = try await WebFetcher(timeout: 60, maxBytes: 64 * 1024 * 1024).get(ModelsDevCatalog.apiURL)
        XCTAssertGreaterThan(ModelsDevCatalog.parse(apiJSON: data, region: .international).count, 10)
    }

    func testHuggingFaceStillParses() async throws {
        let info = await HuggingFaceClient().fetch(modelID: "Qwen/Qwen3-8B")
        XCTAssertEqual(try XCTUnwrap(info?.parameters?.totalB), 8.19, accuracy: 0.1)
    }

    func testExchangeRatesStillParse() async throws {
        let rates = try await ExchangeRateClient().fetch(base: .cny)
        XCTAssertNotNil(rates.rate(from: .cny, to: .jpy))
    }
}
