import Foundation

/// 再試行のルール。
///
/// 料金が二重にかからないよう、既定では GET（モデル一覧・残高など）だけを自動再試行します。
/// チャット等の POST はユーザーが「再試行」を押したときだけ送り直します。
public struct RetryPolicy: Sendable, Equatable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxRetries: Int = 2, baseDelay: TimeInterval = 0.8, maxDelay: TimeInterval = 8) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let none = RetryPolicy(maxRetries: 0)
    public static let standard = RetryPolicy()

    /// n 回目（0 始まり）の再試行までの待ち時間
    public func delay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return min(maxDelay, retryAfter) }
        let exponential = baseDelay * pow(2, Double(max(0, attempt)))
        return min(maxDelay, exponential)
    }

    /// その失敗が再試行で直る可能性があるか
    public func shouldRetry(_ error: SiliconFlowError, attempt: Int) -> Bool {
        guard attempt < maxRetries else { return false }
        switch error.kind {
        case .rateLimited, .overloaded, .gatewayTimeout, .badGateway, .serverError, .timedOut, .connectionFailed:
            return true
        default:
            return false
        }
    }
}
