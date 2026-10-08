import Foundation

/// 認証の要らない Web 上の情報（カタログ・Hugging Face・為替）を取得します。
public struct WebFetcher: Sendable {
    public let transport: HTTPTransport
    public var retryPolicy: RetryPolicy
    public var timeout: TimeInterval
    public var maxBytes: Int
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        transport: HTTPTransport = SharedTransport.default,
        retryPolicy: RetryPolicy = RetryPolicy(maxRetries: 1),
        timeout: TimeInterval = 30,
        maxBytes: Int = 12 * 1024 * 1024
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.timeout = timeout
        self.maxBytes = maxBytes
        self.sleep = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    }

    public func get(_ url: URL, accept: String = "application/json, text/html;q=0.9, */*;q=0.8") async throws -> Data {
        let request = HTTPRequest(
            method: .get,
            url: url,
            headers: [
                "Accept": accept,
                "User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) SiliconFlowLab/1.0",
            ],
            timeout: timeout
        )
        let endpoint = "GET \(url.host ?? "")\(url.path)"
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, head) = try await transport.send(request)
                guard head.isSuccess else {
                    throw SiliconFlowError.http(status: head.statusCode, body: data, head: head, endpoint: endpoint, region: nil)
                }
                guard data.count <= maxBytes else {
                    throw SiliconFlowError(kind: .payloadTooLarge, endpoint: endpoint, underlying: "\(data.count) bytes")
                }
                return data
            } catch {
                let wrapped = SiliconFlowError.wrap(error, endpoint: endpoint)
                guard wrapped.kind != .cancelled, retryPolicy.shouldRetry(wrapped, attempt: attempt) else { throw wrapped }
                let delay = retryPolicy.delay(forAttempt: attempt, retryAfter: wrapped.retryAfter)
                attempt += 1
                try await sleep(delay)
            }
        }
    }
}
