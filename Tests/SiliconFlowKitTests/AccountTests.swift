import XCTest
@testable import SiliconFlowKit

/// 残高照会 API（GET /user/info）の提供終了への対応
///
/// 実際の応答（中国版、2026-08-14 以降）:
/// HTTP 410 `{"code":20092,"message":"This endpoint is deprecated and is no longer available.","data":null}`
final class RetiredUserInfoTests: XCTestCase {
    static let retiredBody = #"{"code":20092,"message":"This endpoint is deprecated and is no longer available.","data":null}"#

    func testRetiredEndpointIsNotAKeyProblem() async {
        let transport = MockTransport(.json(Self.retiredBody, status: 410))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).userInfo() }
        XCTAssertEqual(error?.kind, .endpointRetired)
        XCTAssertEqual(error?.apiCode, 20092)
        XCTAssertEqual(error?.httpStatus, 410)
        XCTAssertEqual(transport.requests.count, 1, "提供終了は再試行しない")
        let diagnosis = error?.diagnosis
        XCTAssertEqual(diagnosis?.severity, .info)
        XCTAssertTrue(diagnosis?.title.contains("残高照会 API") ?? false, diagnosis?.title ?? "")
        XCTAssertTrue(diagnosis?.cause.contains("API キーや設定の問題ではなく") ?? false)
        XCTAssertTrue(diagnosis?.actions.contains(.openURL(title: "コンソールを開く", url: APIRegion.china.consoleURL)) ?? false)
    }

    func testClassifierSeparatesRetiredEndpointsFromRetiredModels() {
        let retired = APIErrorBody.parse(text: Self.retiredBody)
        XCTAssertEqual(FailureClassifier.classify(status: 410, body: retired, endpoint: "GET /user/info"), .endpointRetired)
        XCTAssertEqual(FailureClassifier.classify(status: nil, body: retired, endpoint: "GET /user/info"), .endpointRetired, "200 に埋め込まれても同じ")
        XCTAssertEqual(FailureClassifier.classify(status: 410, body: APIErrorBody(), endpoint: "GET /user/info"), .endpointRetired, "本文が空の 410")
        XCTAssertEqual(FailureClassifier.classify(status: 410, body: APIErrorBody(message: "Gone"), endpoint: "POST /video/submit"), .endpointRetired)
        let model = APIErrorBody(message: "The model has been deprecated, please use a newer one.")
        XCTAssertEqual(FailureClassifier.classify(status: 400, body: model, endpoint: "POST /chat/completions"), .modelDeprecated)
        XCTAssertEqual(FailureClassifier.classify(status: 410, body: APIErrorBody(message: "Model is gone"), endpoint: "POST /chat/completions"), .modelDeprecated)
        let chinese = APIErrorBody(message: "/user/info 接口已停止服务")
        XCTAssertEqual(FailureClassifier.classify(status: 404, body: chinese, endpoint: "GET /user/info"), .endpointRetired)
        XCTAssertEqual(FailureClassifier.classify(status: 401, body: APIErrorBody(code: 30014, message: "Token is invalid."), endpoint: "GET /user/info"), .invalidAPIKey, "無効なキーは今までどおり")
    }

    func testOtherRetiredEndpointsGetGenericAdvice() {
        let error = SiliconFlowError(kind: .endpointRetired, endpoint: "POST /video/submit", httpStatus: 410, apiCode: 20092, region: .international)
        XCTAssertTrue(error.diagnosis.title.contains("この API は提供終了しました"))
        XCTAssertTrue(error.diagnosis.actions.contains(.openURL(title: "公式のお知らせを開く", url: APIRegion.international.releaseNotesURL)))
    }

    func testUserInfoIgnoresFailureCodesAndNullData() {
        XCTAssertNil(UserInfo.parse(Data(#"{"code":20092,"message":"deprecated","data":{"id":"u"}}"#.utf8)), "失敗コードなら中身を信用しない")
        XCTAssertNil(UserInfo.parse(Data(#"{"code":20000,"data":null,"id":"request-id"}"#.utf8)), "data が null のとき直下の id を使わない")
        XCTAssertNil(UserInfo.parse(Data(#"{"code":"20092","data":null}"#.utf8)), "文字列のコードも判定する")
        XCTAssertEqual(UserInfo.parse(Data(#"{"code":200,"data":{"id":"u","totalBalance":"1"}}"#.utf8))?.totalBalance, 1)
        XCTAssertEqual(UserInfo.parse(Data(#"{"id":"u","balance":2}"#.utf8))?.balance, 2, "data の無い形式")
    }

    func testEmbeddedRetiredCodeIn200IsDetected() async {
        let transport = MockTransport(.json(Self.retiredBody))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).userInfo() }
        XCTAssertEqual(error?.kind, .endpointRetired)
    }

    func testEmptyUserInfoIsEmptyResponse() async {
        let transport = MockTransport(MockTransport.Reply(status: 200, headers: ["Content-Type": "application/json"], body: Data()))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).userInfo() }
        XCTAssertEqual(error?.kind, .emptyResponse)
    }
}

final class BalanceLookupTests: XCTestCase {
    func testLookupOutcomes() async {
        let retired = await makeClient(MockTransport(.json(RetiredUserInfoTests.retiredBody, status: 410))).lookUpBalance()
        XCTAssertEqual(retired, .unsupported)
        let missing = await makeClient(MockTransport(.text("404 page not found", status: 404))).lookUpBalance()
        XCTAssertEqual(missing, .unsupported, "経路ごと消えた場合（404）も使えない扱い")
        let invalid = await makeClient(MockTransport(.json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401))).lookUpBalance()
        guard case .failed(let error) = invalid else { return XCTFail("\(invalid)") }
        XCTAssertEqual(error.kind, .invalidAPIKey)
        let ok = await makeClient(MockTransport(.json(#"{"code":20000,"data":{"id":"u","totalBalance":"3.5"}}"#))).lookUpBalance()
        XCTAssertEqual(ok.userInfo?.effectiveTotal, 3.5)
        let offline = await makeClient(MockTransport(.failure(URLError(.notConnectedToInternet))), retry: .none).lookUpBalance()
        guard case .failed(let network) = offline else { return XCTFail("\(offline)") }
        XCTAssertEqual(network.kind, .offline)
    }

    func testSupportRecordSkipsRetiredEndpointUntilRecheck() throws {
        let base = try XCTUnwrap(URL(string: "https://api.siliconflow.cn/v1"))
        let other = try XCTUnwrap(URL(string: "https://api.siliconflow.com/v1"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var record = BalanceSupportRecord()
        XCTAssertTrue(record.shouldLookUp(baseURL: base, now: start))
        XCTAssertFalse(record.record(.failed(SiliconFlowError(kind: .offline)), baseURL: base, now: start), "一時的な失敗は覚えない")
        XCTAssertTrue(record.record(.unsupported, baseURL: base, now: start))
        XCTAssertFalse(record.shouldLookUp(baseURL: base, now: start.addingTimeInterval(3600)))
        XCTAssertFalse(record.shouldLookUp(baseURL: try XCTUnwrap(URL(string: "https://API.siliconflow.cn/v1/")), now: start), "表記ゆれは同じ接続先")
        XCTAssertTrue(record.shouldLookUp(baseURL: other, now: start), "リージョンごとに別々")
        XCTAssertTrue(record.shouldLookUp(baseURL: base, now: start.addingTimeInterval(BalanceSupportRecord.recheckInterval)), "7 日たったら確かめ直す")
        XCTAssertTrue(record.shouldLookUp(baseURL: base, now: start.addingTimeInterval(-60)), "時計が戻っても永久に止まらない")
        let restored = try JSONDecoder().decode(BalanceSupportRecord.self, from: try JSONEncoder().encode(record))
        XCTAssertEqual(restored, record)
        XCTAssertTrue(record.record(.available(UserInfo(totalBalance: 1)), baseURL: base, now: start), "使えるようになったら忘れる")
        XCTAssertTrue(record.shouldLookUp(baseURL: base, now: start))
    }
}

final class KeyCheckTests: XCTestCase {
    private let key = "sk-abcdefghijklmnopqrstuvwxyz"

    func testAuthenticationStepUsesModelsNotUserInfo() async {
        let transport = MockTransport { request, _ in
            switch request.url.path {
            case "/v1/models": return .json(#"{"data":[{"id":"Qwen/Qwen3-8B"},{"id":"BAAI/bge-m3"}]}"#)
            default: return .json(RetiredUserInfoTests.retiredBody, status: 410)
            }
        }
        let diagnostics = ConnectionDiagnostics(client: makeClient(transport))
        let auth = await diagnostics.run(.authentication, testModel: nil)
        guard case .passed(let message) = auth else { return XCTFail("\(auth)") }
        XCTAssertTrue(message.contains("2 個のモデル"), message)
        XCTAssertEqual(transport.requests.map(\.url.path), ["/v1/models"])
        let balance = await diagnostics.run(.balance, testModel: nil)
        guard case .skipped(let note) = balance else { return XCTFail("\(balance)") }
        XCTAssertTrue(note.contains("提供終了"), note)
        XCTAssertFalse(balance.isFailure)
        XCTAssertTrue(DiagnosticStep.authentication.blocksLaterSteps)
        XCTAssertFalse(DiagnosticStep.balance.blocksLaterSteps, "残高が取れなくても後の項目は続ける")
    }

    func testBalanceStepNeverFails() async {
        let transport = MockTransport(.json(#"{"code":50000,"message":"internal"}"#, status: 500))
        let outcome = await ConnectionDiagnostics(client: makeClient(transport, retry: .none)).run(.balance, testModel: nil)
        guard case .warning(let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(message.contains("モデルの利用には影響しません"))
        let negative = ConnectionDiagnostics.describe(UserInfo(chargeBalance: -3, totalBalance: -3), currency: .cny)
        guard case .warning(let text) = negative else { return XCTFail("\(negative)") }
        XCTAssertTrue(text.contains("マイナス"))
    }

    func testRestrictedAccountStillIdentifiesRegion() async {
        let transport = MockTransport { request, _ in
            if request.url.host == "api.siliconflow.cn" {
                return .json(#"{"code":30001,"message":"Sorry, your account balance is insufficient","data":null}"#, status: 402)
            }
            return .json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401)
        }
        let (result, errors) = await RegionDetector.detect(apiKey: key, preferred: .international, transport: transport)
        XCTAssertEqual(result?.region, .china, "402/403 はキーが通った証拠")
        XCTAssertEqual(result?.restriction?.kind, .insufficientBalance)
        XCTAssertEqual(errors[.international]?.kind, .invalidAPIKey)
    }

    func testProxyHTMLForbiddenDoesNotCountAsAccepted() async {
        let transport = MockTransport(.text("<html><head><title>403 Forbidden</title></head><body>blocked</body></html>", status: 403, contentType: "text/html"))
        let outcome = await RegionDetector.check(apiKey: key, region: .china, transport: transport)
        guard case .failure(let error) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(error.httpStatus, 403)
    }

    func testCleanRegionWinsOverRestrictedOne() {
        let restricted = RegionDetector.Result(region: .china, restriction: SiliconFlowError(kind: .realNameRequired, httpStatus: 403))
        let clean = RegionDetector.Result(region: .international, modelCount: 3)
        let (best, errors) = RegionDetector.pick(from: [.china: .success(restricted), .international: .success(clean)], order: [.china, .international])
        XCTAssertEqual(best, clean)
        XCTAssertTrue(errors.isEmpty)
    }
}
