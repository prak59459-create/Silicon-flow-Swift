import Foundation
import XCTest
@testable import SiliconFlowKit

/// テスト用の通信モック。URL ごとに応答を返します。
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()
        /// ストリーミング時に送る行（nil なら body を行分割）
        var lines: [String]?
        /// ストリーミングの途中で投げるエラー（lines を送った後）
        var streamError: Error?
        /// 送信そのものを失敗させる
        var error: Error?

        static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            var merged = ["Content-Type": "application/json"]
            for (key, value) in headers { merged[key] = value }
            return Reply(status: status, headers: merged, body: Data(text.utf8))
        }

        static func text(_ text: String, status: Int, contentType: String = "text/plain") -> Reply {
            Reply(status: status, headers: ["Content-Type": contentType], body: Data(text.utf8))
        }

        static func sse(_ lines: [String], streamError: Error? = nil) -> Reply {
            Reply(status: 200, headers: ["Content-Type": "text/event-stream"], lines: lines, streamError: streamError)
        }

        static func failure(_ error: Error) -> Reply {
            Reply(error: error)
        }
    }

    private let lock = NSLock()
    private var handler: (HTTPRequest, Int) -> Reply
    private var recorded: [HTTPRequest] = []

    /// handler には (リクエスト, そのリクエストが何回目か) が渡されます。
    init(handler: @escaping (HTTPRequest, Int) -> Reply) {
        self.handler = handler
    }

    convenience init(_ reply: Reply) {
        self.init { _, _ in reply }
    }

    var requests: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: HTTPRequest) -> Reply {
        lock.lock()
        recorded.append(request)
        let count = recorded.count
        let currentHandler = handler
        lock.unlock()
        return currentHandler(request, count)
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponseHead) {
        let reply = record(request)
        if let error = reply.error { throw error }
        return (reply.body, HTTPResponseHead(statusCode: reply.status, headers: reply.headers))
    }

    func streamLines(_ request: HTTPRequest) async throws -> HTTPLineStream {
        let reply = record(request)
        if let error = reply.error { throw error }
        let lines = reply.lines ?? LineSplitter.lines(in: reply.body)
        let streamError = reply.streamError
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines { continuation.yield(line) }
            if let streamError {
                continuation.finish(throwing: streamError)
            } else {
                continuation.finish()
            }
        }
        return HTTPLineStream(head: HTTPResponseHead(statusCode: reply.status, headers: reply.headers), lines: stream)
    }
}

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name) not found")
        }
        return try Data(contentsOf: url)
    }
}

extension XCTestCase {
    /// SiliconFlowError を投げることを確認し、その値を返します。
    func assertThrowsSiliconFlowError<T>(
        _ expression: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SiliconFlowError? {
        do {
            _ = try await expression()
            XCTFail("エラーが投げられませんでした", file: file, line: line)
            return nil
        } catch let error as SiliconFlowError {
            return error
        } catch {
            XCTFail("SiliconFlowError 以外のエラー: \(error)", file: file, line: line)
            return nil
        }
    }

    func makeClient(_ transport: MockTransport, key: String = "sk-test1234567890abcdefghijklmnop", region: APIRegion = .china, retry: RetryPolicy = .standard) -> SiliconFlowClient {
        var client = SiliconFlowClient(configuration: ClientConfiguration(region: region, apiKey: key), transport: transport, retryPolicy: retry)
        client.sleep = { _ in }
        return client
    }
}
