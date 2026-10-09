import Foundation

/// SiliconFlow API クライアント。
///
/// すべての失敗は `SiliconFlowError` として投げられ、`diagnosis` で原因と直し方が分かります。
public struct SiliconFlowClient: Sendable {
    public let configuration: ClientConfiguration
    public let transport: HTTPTransport
    public var retryPolicy: RetryPolicy
    /// 再試行の待機（テストでは即時に差し替えます）
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        configuration: ClientConfiguration,
        transport: HTTPTransport = SharedTransport.default,
        retryPolicy: RetryPolicy = .standard
    ) {
        self.configuration = configuration
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.sleep = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    }

    public var region: APIRegion { configuration.region }

    // MARK: - リクエストの組み立て

    func makeRequest(
        _ method: HTTPRequest.Method,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = "application/json",
        accept: String = "application/json"
    ) throws -> HTTPRequest {
        let validation = APIKeyValidator.validate(configuration.apiKey)
        if validation.issues.contains(.empty) {
            throw SiliconFlowError(kind: .missingAPIKey, endpoint: Self.label(method, path), region: region)
        }
        if !validation.isUsable {
            throw SiliconFlowError(
                kind: .malformedAPIKey,
                endpoint: Self.label(method, path),
                underlying: validation.issues.map(\.message).joined(separator: " "),
                region: region
            )
        }
        var url = configuration.baseURL.appendingPathComponent(path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            if let withQuery = components.url { url = withQuery }
        }
        var headers = [
            "Authorization": "Bearer \(validation.sanitizedKey)",
            "Accept": accept,
            "User-Agent": configuration.userAgent,
        ]
        if body != nil, let contentType { headers["Content-Type"] = contentType }
        return HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: configuration.requestTimeout)
    }

    static func label(_ method: HTTPRequest.Method, _ path: String) -> String {
        "\(method.rawValue) /\(path)"
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SiliconFlowError(kind: .invalidRequest, underlying: "リクエストの JSON 変換に失敗: \(error)", region: region)
        }
    }

    // MARK: - 送信

    /// 送信し、2xx 以外なら SiliconFlowError を投げます（必要なら再試行）。
    func send(_ request: HTTPRequest, endpoint: String, modelID: String?, retry: RetryPolicy) async throws -> (Data, HTTPResponseHead) {
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                let (data, head) = try await transport.send(request)
                if head.isSuccess { return (data, head) }
                throw SiliconFlowError.http(status: head.statusCode, body: data, head: head, endpoint: endpoint, region: region, modelID: modelID)
            } catch {
                let wrapped = SiliconFlowError.wrap(error, endpoint: endpoint, region: region, modelID: modelID)
                guard wrapped.kind != .cancelled, retry.shouldRetry(wrapped, attempt: attempt) else { throw wrapped }
                let delay = retry.delay(forAttempt: attempt, retryAfter: wrapped.retryAfter)
                attempt += 1
                try await sleep(delay)
            }
        }
    }

    /// 送信して JSON をデコードします。デコードできない 200 応答に埋め込まれたエラーも検出します。
    func sendDecodable<T: Decodable>(
        _ type: T.Type,
        request: HTTPRequest,
        endpoint: String,
        modelID: String? = nil,
        retry: RetryPolicy
    ) async throws -> T {
        let (data, head) = try await send(request, endpoint: endpoint, modelID: modelID, retry: retry)
        return try decode(type, from: data, head: head, endpoint: endpoint, modelID: modelID)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data, head: HTTPResponseHead, endpoint: String, modelID: String?) throws -> T {
        if data.isEmpty {
            throw SiliconFlowError(kind: .emptyResponse, endpoint: endpoint, httpStatus: head.statusCode, traceID: head.traceID, region: region, modelID: modelID)
        }
        let decoded: T
        do {
            decoded = try JSONDecoder().decode(type, from: data)
        } catch {
            throw describeUndecodable(data, head: head, endpoint: endpoint, modelID: modelID, decodingError: error)
        }
        return decoded
    }

    /// 2xx 応答の本文に埋め込まれたエラー（`{"code":20012,"message":"..."}` など）を取り出します。
    func embeddedError(in data: Data, head: HTTPResponseHead, endpoint: String, modelID: String?) -> SiliconFlowError? {
        guard let json = JSONValue.parse(data), let body = APIErrorBody.fromObject(json) else { return nil }
        var error = SiliconFlowError.fromAPIError(body, status: nil, head: head, endpoint: endpoint, region: region, modelID: modelID)
        error.httpStatus = head.statusCode
        error.bodySnippet = TextSanitizer.snippet(String(decoding: data.prefix(2048), as: UTF8.self))
        return error
    }

    /// 結果が空だったときのエラー（本文にエラーが埋め込まれていればそちらを優先）
    func emptyResultError(_ data: Data, head: HTTPResponseHead, endpoint: String, modelID: String?) -> SiliconFlowError {
        embeddedError(in: data, head: head, endpoint: endpoint, modelID: modelID)
            ?? SiliconFlowError(kind: .emptyResponse, endpoint: endpoint, httpStatus: head.statusCode, traceID: head.traceID, region: region, modelID: modelID)
    }

    /// 期待した形で読めなかった 2xx 応答の正体を調べます。
    func describeUndecodable(_ data: Data, head: HTTPResponseHead, endpoint: String, modelID: String?, decodingError: Error?) -> SiliconFlowError {
        if let embedded = embeddedError(in: data, head: head, endpoint: endpoint, modelID: modelID) {
            return embedded
        }
        let body = APIErrorBody.parse(data)
        if body.isHTML || head.contentType?.contains("text/html") == true {
            return SiliconFlowError(
                kind: .unexpectedResponse, endpoint: endpoint, httpStatus: head.statusCode, traceID: head.traceID,
                region: region, modelID: modelID, bodySnippet: body.rawSnippet
            )
        }
        var error = SiliconFlowError.wrap(decodingError ?? SiliconFlowError(kind: .decodingFailed), endpoint: endpoint, region: region, modelID: modelID)
        if error.kind != .decodingFailed { error.kind = .decodingFailed }
        error.httpStatus = head.statusCode
        error.traceID = head.traceID
        error.bodySnippet = body.rawSnippet
        return error
    }
}

/// アプリ全体で共有する通信オブジェクト（URLSession を何個も作らないため）
public enum SharedTransport {
    public static let `default`: HTTPTransport = URLSessionTransport.makeDefault()
}
