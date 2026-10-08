import XCTest
@testable import SiliconFlowKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class APIErrorBodyTests: XCTestCase {
    func testSiliconFlowJSONObject() {
        let body = APIErrorBody.parse(text: #"{"code":30014,"data":null,"message":"Token is invalid."}"#)
        XCTAssertEqual(body.code, 30014)
        XCTAssertEqual(body.message, "Token is invalid.")
        XCTAssertFalse(body.isHTML)
    }

    func testJSONString() {
        XCTAssertEqual(APIErrorBody.parse(text: #""Invalid token""#).message, "Invalid token")
    }

    func testPlainText() {
        XCTAssertEqual(APIErrorBody.parse(text: "404 page not found").message, "404 page not found")
    }

    func testOpenAIStyle() {
        let body = APIErrorBody.parse(text: #"{"error":{"message":"bad","type":"invalid_request_error","code":"model_not_found"}}"#)
        XCTAssertEqual(body.message, "bad")
        XCTAssertEqual(body.type, "invalid_request_error")
        XCTAssertEqual(body.codeText, "model_not_found")
    }

    func testHTML() {
        let body = APIErrorBody.parse(text: "<!DOCTYPE html><html><head><title>Wi-Fi Login</title></head></html>")
        XCTAssertTrue(body.isHTML)
        XCTAssertEqual(body.message, "Wi-Fi Login")
    }

    func testEmpty() {
        XCTAssertEqual(APIErrorBody.parse(text: "  "), APIErrorBody())
    }

    func testSuccessObjectIsNotError() {
        XCTAssertNil(APIErrorBody.fromObject(JSONValue.parse(#"{"code":20000,"message":"OK","data":{}}"#)!))
        XCTAssertNil(APIErrorBody.fromObject(JSONValue.parse(#"{"id":"x","choices":[]}"#)!))
    }
}

final class FailureClassifierTests: XCTestCase {
    private func kind(_ status: Int?, _ json: String, endpoint: String? = "POST /chat/completions") -> FailureKind {
        FailureClassifier.classify(status: status, body: APIErrorBody.parse(text: json), endpoint: endpoint)
    }

    func testAuthentication() {
        XCTAssertEqual(kind(401, #"{"code":30014,"message":"Token is invalid."}"#), .invalidAPIKey)
        XCTAssertEqual(kind(401, #""Invalid token""#), .invalidAPIKey)
        XCTAssertEqual(kind(401, ""), .invalidAPIKey)
    }

    func testModelNotFound() {
        XCTAssertEqual(kind(400, #"{"code":20012,"message":"Model does not exist. Please check it carefully.","data":null}"#), .modelNotFound)
        XCTAssertEqual(kind(404, #"{"message":"model not found"}"#), .modelNotFound)
    }

    func testEndpointNotFound() {
        XCTAssertEqual(kind(404, "404 page not found", endpoint: "GET /models"), .endpointNotFound)
        XCTAssertEqual(kind(404, "<html><body>nope</body></html>"), .endpointNotFound)
    }

    func testBalanceAndRealName() {
        XCTAssertEqual(kind(403, #"{"code":30001,"message":"Sorry, your account balance is insufficient"}"#), .insufficientBalance)
        XCTAssertEqual(kind(403, #"{"message":"This model requires real-name authentication"}"#), .realNameRequired)
        XCTAssertEqual(kind(403, #"{"message":"请先完成实名认证"}"#), .realNameRequired)
        XCTAssertEqual(kind(403, #"{"message":"forbidden"}"#), .forbidden)
        XCTAssertEqual(kind(403, #"{"message":"no permission for this model"}"#), .modelAccessDenied)
    }

    func testRequestProblems() {
        XCTAssertEqual(kind(400, #"{"code":20015,"message":"max_tokens must be less than 16384"}"#), .contextTooLong)
        XCTAssertEqual(kind(400, #"{"message":"enable_thinking is not supported for this model"}"#), .unsupportedParameter)
        XCTAssertEqual(kind(400, #"{"message":"invalid temperature"}"#), .invalidRequest)
        XCTAssertEqual(kind(413, ""), .payloadTooLarge)
        XCTAssertEqual(kind(400, #"{"message":"The content contains sensitive words"}"#), .contentFiltered)
    }

    func testServerSide() {
        XCTAssertEqual(kind(429, #"{"message":"Request was rejected due to rate limiting. Details:TPM limit reached."}"#), .rateLimited)
        XCTAssertEqual(kind(503, #"{"code":50505,"message":"Model service overloaded. Please try again later."}"#), .overloaded)
        XCTAssertEqual(kind(504, ""), .gatewayTimeout)
        XCTAssertEqual(kind(500, ""), .serverError)
        XCTAssertEqual(kind(502, "<html>Bad Gateway</html>"), .badGateway)
        XCTAssertEqual(kind(530, ""), .badGateway)
    }

    func testRateLimitDimension() {
        XCTAssertEqual(FailureClassifier.rateLimitDimension(in: "Details:TPM limit reached."), "TPM")
        XCTAssertEqual(FailureClassifier.rateLimitDimension(in: "rpd exceeded"), "RPD")
        XCTAssertNil(FailureClassifier.rateLimitDimension(in: "slow down"))
    }

    func testURLErrors() {
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .notConnectedToInternet), .offline)
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .timedOut), .timedOut)
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .cannotFindHost), .dnsFailure)
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .networkConnectionLost), .connectionFailed)
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .serverCertificateUntrusted), .tlsFailure)
        XCTAssertEqual(FailureClassifier.classify(urlErrorCode: .cancelled), .cancelled)
    }

    func testWrapConvertsKnownErrorTypes() {
        XCTAssertEqual(SiliconFlowError.wrap(URLError(.timedOut)).kind, .timedOut)
        XCTAssertEqual(SiliconFlowError.wrap(CancellationError()).kind, .cancelled)
        let decoding = DecodingError.keyNotFound(TestKey.id, .init(codingPath: [], debugDescription: "x"))
        let wrapped = SiliconFlowError.wrap(decoding)
        XCTAssertEqual(wrapped.kind, .decodingFailed)
        XCTAssertTrue(wrapped.underlying?.contains("id") ?? false)
        let existing = SiliconFlowError(kind: .rateLimited)
        XCTAssertEqual(SiliconFlowError.wrap(existing, endpoint: "GET /models").endpoint, "GET /models")
    }

    private enum TestKey: String, CodingKey { case id }
}

final class ErrorDiagnoserTests: XCTestCase {
    func testEveryKindHasActionableDiagnosis() {
        for kind in FailureKind.allCases {
            for region in APIRegion.allCases {
                let error = SiliconFlowError(kind: kind, endpoint: "POST /chat/completions", httpStatus: 400, apiCode: 1, serverMessage: "msg", region: region, modelID: "a/b")
                let diagnosis = error.diagnosis
                XCTAssertEqual(diagnosis.kind, kind, "\(kind)")
                XCTAssertFalse(diagnosis.title.isEmpty, "\(kind)")
                XCTAssertFalse(diagnosis.cause.isEmpty, "\(kind)")
                XCTAssertFalse(diagnosis.fixes.isEmpty, "\(kind) には直し方が必要")
                XCTAssertTrue(diagnosis.fixes.allSatisfy { !$0.isEmpty })
                XCTAssertFalse(diagnosis.actions.isEmpty, "\(kind) には操作ボタンが必要")
                for action in diagnosis.actions {
                    XCTAssertFalse(action.title.isEmpty)
                    XCTAssertFalse(action.systemImage.isEmpty)
                }
            }
        }
    }

    func testInvalidKeySuggestsOtherRegion() {
        let diagnosis = SiliconFlowError(kind: .invalidAPIKey, httpStatus: 401, apiCode: 30014, serverMessage: "Token is invalid.", region: .china).diagnosis
        XCTAssertTrue(diagnosis.actions.contains(.switchRegion(.international)))
        XCTAssertTrue(diagnosis.cause.contains("Token is invalid."))
        XCTAssertTrue(diagnosis.title.contains("HTTP 401"))
        XCTAssertTrue(diagnosis.title.contains("30014"))
    }

    func testRateLimitMentionsDimensionAndWait() {
        let error = SiliconFlowError(kind: .rateLimited, httpStatus: 429, serverMessage: "TPM limit reached", retryAfter: 12, region: .china)
        let diagnosis = error.diagnosis
        XCTAssertTrue(diagnosis.cause.contains("TPM"))
        XCTAssertTrue(diagnosis.fixes[0].contains("12"))
        XCTAssertTrue(diagnosis.isRetryable)
    }

    func testTechnicalReportContainsDetails() {
        let error = SiliconFlowError(kind: .serverError, endpoint: "POST /chat/completions", httpStatus: 500, apiCode: 50000, serverMessage: "boom", traceID: "trace-1", region: .international, modelID: "Qwen/Qwen3-8B")
        let report = error.technicalReport
        for needle in ["POST /chat/completions", "500", "50000", "boom", "trace-1", "Qwen/Qwen3-8B", "国際版"] {
            XCTAssertTrue(report.contains(needle), needle)
        }
        XCTAssertEqual(error.errorDescription, error.diagnosis.title)
    }

    func testRetryPolicy() {
        let policy = RetryPolicy(maxRetries: 2, baseDelay: 1, maxDelay: 5)
        XCTAssertTrue(policy.shouldRetry(SiliconFlowError(kind: .overloaded), attempt: 0))
        XCTAssertFalse(policy.shouldRetry(SiliconFlowError(kind: .overloaded), attempt: 2))
        XCTAssertFalse(policy.shouldRetry(SiliconFlowError(kind: .invalidAPIKey), attempt: 0))
        XCTAssertEqual(policy.delay(forAttempt: 0, retryAfter: nil), 1)
        XCTAssertEqual(policy.delay(forAttempt: 2, retryAfter: nil), 4)
        XCTAssertEqual(policy.delay(forAttempt: 5, retryAfter: nil), 5)
        XCTAssertEqual(policy.delay(forAttempt: 0, retryAfter: 30), 5)
    }
}
