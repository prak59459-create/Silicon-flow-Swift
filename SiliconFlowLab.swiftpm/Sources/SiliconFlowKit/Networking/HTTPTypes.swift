import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 送信する HTTP リクエスト（URLRequest を Sendable に扱うための薄い型）
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 60) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }

    public var urlRequest: URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

/// 受信した HTTP レスポンスのヘッダ部分
public struct HTTPResponseHead: Sendable, Equatable {
    public var statusCode: Int
    /// キーは小文字
    public var headers: [String: String]

    public init(statusCode: Int, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        var lowered: [String: String] = [:]
        for (key, value) in headers { lowered[key.lowercased()] = value }
        self.headers = lowered
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public var contentType: String? { header("content-type")?.lowercased() }

    /// SiliconFlow が返すトレース ID（サポートへの問い合わせ時に役立ちます）
    public var traceID: String? {
        header("x-siliconcloud-trace-id") ?? header("x-siliconflow-trace-id") ?? header("x-request-id") ?? header("trace-id")
    }

    /// Retry-After ヘッダ（秒）
    public var retryAfter: TimeInterval? {
        guard let value = header("retry-after"), let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        return max(0, seconds)
    }

    init(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        self.init(statusCode: http.statusCode, headers: headers)
    }
}

/// 行単位で流れてくるレスポンス（ストリーミング用）
public struct HTTPLineStream: Sendable {
    public var head: HTTPResponseHead
    public var lines: AsyncThrowingStream<String, Error>

    public init(head: HTTPResponseHead, lines: AsyncThrowingStream<String, Error>) {
        self.head = head
        self.lines = lines
    }

    /// 行をすべて読み、本文として連結します（エラー応答の読み取り用）。
    public func collectBody(maxBytes: Int = 64 * 1024) async throws -> Data {
        var data = Data()
        for try await line in lines {
            data.append(contentsOf: line.utf8)
            data.append(0x0A)
            if data.count >= maxBytes { break }
        }
        return data
    }
}

/// HTTP 通信の抽象化。テストではモックに差し替えます。
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponseHead)
    func streamLines(_ request: HTTPRequest) async throws -> HTTPLineStream
}
