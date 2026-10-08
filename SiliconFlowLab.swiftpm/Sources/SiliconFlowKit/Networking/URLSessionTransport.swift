import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession による実際の通信。
///
/// - Apple プラットフォーム: `bytes(for:)` で本当に逐次ストリーミングします。
/// - Linux（CI のテスト用）: 全体を受信してから行に分割します。
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// キャッシュを使わない（メモリ節約）・リソース全体の上限 15 分の既定設定
    public static func makeDefault() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    public func send(_ request: HTTPRequest) async throws -> (Data, HTTPResponseHead) {
        #if canImport(FoundationNetworking)
        return try await dataTask(request.urlRequest)
        #else
        let (data, response) = try await session.data(for: request.urlRequest)
        return (data, try HTTPResponseHead(response: response))
        #endif
    }

    public func streamLines(_ request: HTTPRequest) async throws -> HTTPLineStream {
        #if canImport(FoundationNetworking)
        let (data, head) = try await dataTask(request.urlRequest)
        let lines = LineSplitter.lines(in: data)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
        return HTTPLineStream(head: head, lines: stream)
        #else
        let (bytes, response) = try await session.bytes(for: request.urlRequest)
        let head = try HTTPResponseHead(response: response)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    var splitter = LineSplitter()
                    for try await byte in bytes {
                        if let line = splitter.append(byte) {
                            continuation.yield(line)
                        }
                    }
                    if let last = splitter.finish() {
                        continuation.yield(last)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return HTTPLineStream(head: head, lines: stream)
        #endif
    }

    #if canImport(FoundationNetworking)
    private func dataTask(_ request: URLRequest) async throws -> (Data, HTTPResponseHead) {
        let box = CancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPResponseHead), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    do {
                        continuation.resume(returning: (data ?? Data(), try HTTPResponseHead(response: response)))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.store(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
    #endif
}

#if canImport(FoundationNetworking)
/// キャンセル処理用に URLSessionTask を保持する箱
private final class CancellableTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func store(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }
}
#endif
