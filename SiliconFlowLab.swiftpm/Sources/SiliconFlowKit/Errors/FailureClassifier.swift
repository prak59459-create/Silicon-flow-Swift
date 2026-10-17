import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP ステータス・SiliconFlow のエラーコード・メッセージから失敗の種類を判定します。
public enum FailureClassifier {
    /// SiliconFlow の既知のエラーコード
    public enum KnownCode {
        public static let modelNotFound = 20012
        public static let invalidToken = 30014
        public static let insufficientBalance = 30001
        public static let overloaded = 50505
        /// API の提供終了（例: 2026-08-14 に停止した `GET /user/info` は HTTP 410 とこのコードを返します）
        public static let endpointRetired = 20092
    }

    public static func classify(status: Int?, body: APIErrorBody, endpoint: String?) -> FailureKind {
        let message = (body.message ?? "").lowercased()
        let codeText = (body.codeText ?? "").lowercased()

        // まずメッセージ・コードで判定できるもの（ステータスより具体的）
        if body.code == KnownCode.invalidToken || matches(message, ["token is invalid", "invalid token", "invalid api key", "incorrect api key", "unauthorized", "api key is invalid", "令牌无效"]) {
            return .invalidAPIKey
        }
        // 「deprecated」はモデルの提供終了にも使われるので、API の終了はその前に見分けます
        if isRetiredEndpoint(code: body.code, status: status, message: message) {
            return .endpointRetired
        }
        if body.code == KnownCode.modelNotFound || matches(message, ["model does not exist", "model not exist", "model not found", "模型不存在", "no such model"]) || codeText == "model_not_found" {
            return .modelNotFound
        }
        if matches(message, ["deprecated", "has been offline", "下线", "已下架", "no longer available"]) {
            return .modelDeprecated
        }
        if body.code == KnownCode.insufficientBalance || matches(message, ["insufficient balance", "balance is insufficient", "balance insufficient", "balance is not enough", "not enough balance", "insufficient_quota", "quota exceeded", "余额不足", "欠费", "arrear"]) || codeText == "insufficient_quota" {
            return .insufficientBalance
        }
        if matches(message, ["real-name", "real name", "realname", "实名", "identity verification", "kyc"]) {
            return .realNameRequired
        }
        if matches(message, ["sensitive", "content_filter", "content filter", "inappropriate", "敏感", "违规", "moderation"]) {
            return .contentFiltered
        }
        if body.code == KnownCode.overloaded || matches(message, ["overloaded", "too busy", "繁忙", "过载", "capacity"]) {
            return status == 429 ? .rateLimited : .overloaded
        }
        if matches(message, ["rate limit", "rate limiting", "too many requests", "tpm limit", "rpm limit", "限流", "请求过于频繁"]) {
            return .rateLimited
        }
        if matches(message, ["context length", "maximum context", "context_length", "too long", "exceeds the model", "max_tokens", "max_new_tokens", "maximum length", "input length", "token limit", "超过", "超出"]) {
            return .contextTooLong
        }
        if matches(message, ["enable_thinking", "thinking_budget", "not support", "unsupported", "unknown parameter", "unrecognized", "extra fields", "不支持"]) {
            return .unsupportedParameter
        }

        guard let status else {
            if body.isHTML { return .unexpectedResponse }
            return body.code != nil || body.message != nil ? .invalidRequest : .unknown
        }

        switch status {
        case 400, 422:
            return body.isHTML ? .unexpectedResponse : .invalidRequest
        case 401:
            return .invalidAPIKey
        case 402:
            return .insufficientBalance
        case 403:
            if matches(message, ["model", "模型", "permission", "access", "权限"]) { return .modelAccessDenied }
            return .forbidden
        case 404:
            if matches(message, ["404 page not found", "page not found", "not found"]) && !message.contains("model") { return .endpointNotFound }
            if body.isHTML { return .endpointNotFound }
            return endpointLooksModelSpecific(endpoint) ? .modelNotFound : .endpointNotFound
        case 408:
            return .timedOut
        case 410:
            // モデルに触れた 410 だけがここに来ます（それ以外は API の提供終了として判定済み）
            return .modelDeprecated
        case 413:
            return .payloadTooLarge
        case 429:
            return .rateLimited
        case 500:
            return .serverError
        case 502:
            return .badGateway
        case 503:
            return .overloaded
        case 504:
            return .gatewayTimeout
        case 520...599:
            return .badGateway
        default:
            if body.isHTML { return .unexpectedResponse }
            return (400..<500).contains(status) ? .invalidRequest : .serverError
        }
    }

    public static func classify(urlErrorCode code: URLError.Code) -> FailureKind {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsFailure
        case .cannotConnectToHost, .networkConnectionLost, .resourceUnavailable, .cannotLoadFromNetwork:
            return .connectionFailed
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return .tlsFailure
        case .cancelled, .userCancelledAuthentication:
            return .cancelled
        case .badURL, .unsupportedURL:
            return .invalidBaseURL
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData:
            return .unexpectedResponse
        case .zeroByteResource:
            return .emptyResponse
        case .userAuthenticationRequired:
            return .invalidAPIKey
        case .dataLengthExceedsMaximum:
            return .payloadTooLarge
        default:
            return .connectionFailed
        }
    }

    /// 429 のメッセージから、どの上限（RPM/TPM など）に当たったかを取り出します。
    public static func rateLimitDimension(in message: String?) -> String? {
        guard let message = message?.uppercased() else { return nil }
        for dimension in ["TPM", "RPM", "TPD", "RPD", "IPM", "IPD"] where message.contains(dimension) {
            return dimension
        }
        return nil
    }

    /// API そのものが提供終了したことを示す応答か
    ///
    /// 実例: HTTP 410 `{"code":20092,"message":"This endpoint is deprecated and is no longer available.","data":null}`
    static func isRetiredEndpoint(code: Int?, status: Int?, message: String) -> Bool {
        if code == KnownCode.endpointRetired { return true }
        let mentionsModel = matches(message, ["model", "模型"])
        if status == 410 { return !mentionsModel }
        let saysRetired = matches(message, ["deprecated", "no longer available", "has been removed", "停止服务", "不再可用", "已下线", "废弃"])
        let mentionsEndpoint = matches(message, ["endpoint", "api ", "接口"])
        return saysRetired && mentionsEndpoint && !mentionsModel
    }

    static func matches(_ message: String, _ needles: [String]) -> Bool {
        guard !message.isEmpty else { return false }
        return needles.contains { message.contains($0) }
    }

    private static func endpointLooksModelSpecific(_ endpoint: String?) -> Bool {
        guard let endpoint = endpoint?.lowercased() else { return false }
        return endpoint.hasPrefix("post ") && !endpoint.contains("/video/status")
    }
}
