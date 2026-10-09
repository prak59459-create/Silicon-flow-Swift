import Foundation

/// 失敗の種類。原因の説明と直し方はこの分類から決まります。
public enum FailureKind: String, Sendable, CaseIterable, Codable {
    // 入力・設定
    case missingAPIKey
    case malformedAPIKey
    case invalidBaseURL

    // 認証・権限・お金
    case invalidAPIKey
    case forbidden
    case realNameRequired
    case insufficientBalance
    case modelAccessDenied

    // リクエスト内容
    case modelNotFound
    case modelDeprecated
    case endpointNotFound
    case invalidRequest
    case contextTooLong
    case unsupportedParameter
    case payloadTooLarge
    case contentFiltered

    // サーバー側
    case rateLimited
    case serverError
    case badGateway
    case overloaded
    case gatewayTimeout

    // 通信
    case offline
    case timedOut
    case dnsFailure
    case connectionFailed
    case tlsFailure
    case cancelled

    // 応答の形式
    case unexpectedResponse
    case decodingFailed
    case streamInterrupted
    case emptyResponse

    case unknown
}
