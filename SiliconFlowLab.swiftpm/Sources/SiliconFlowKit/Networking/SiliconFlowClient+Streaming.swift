import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension SiliconFlowClient {
    /// チャットをストリーミングで受け取ります。
    ///
    /// - 途中で接続が切れた場合は `.streamInterrupted`（それまでに届いたチャンクは配信済み）
    /// - ストリームの中にエラー JSON が流れてきた場合もエラーとして投げます
    /// - サーバーが SSE ではなく通常の JSON を返した場合も回答として扱います
    public func streamChat(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let endpoint = Self.label(.post, "chat/completions")
                var state = StreamState()
                do {
                    var body = request
                    body.stream = true
                    let http = try makeRequest(.post, path: "chat/completions", body: try encodeJSON(body), accept: "text/event-stream")
                    let stream: HTTPLineStream
                    do {
                        stream = try await transport.streamLines(http)
                    } catch {
                        throw SiliconFlowError.wrap(error, endpoint: endpoint, region: region, modelID: request.model)
                    }
                    state.head = stream.head
                    guard stream.head.isSuccess else {
                        let errorBody = try await stream.collectBody()
                        throw SiliconFlowError.http(status: stream.head.statusCode, body: errorBody, head: stream.head, endpoint: endpoint, region: region, modelID: request.model)
                    }
                    try await consume(stream, state: &state, endpoint: endpoint, model: request.model) { chunk in
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: finalError(error, state: state, endpoint: endpoint, model: request.model))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consume(
        _ stream: HTTPLineStream,
        state: inout StreamState,
        endpoint: String,
        model: String,
        yield: (ChatCompletionChunk) -> Void
    ) async throws {
        let decoder = JSONDecoder()
        var parser = SSEParser()
        for try await line in stream.lines {
            try Task.checkCancellation()
            guard let event = parser.consume(line: line) else { continue }
            if event.isDone {
                state.sawDone = true
                break
            }
            let data = Data(event.data.utf8)
            if let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data), !chunk.choices.isEmpty || chunk.usage != nil {
                state.chunkCount += 1
                if chunk.finishReason != nil { state.sawFinishReason = true }
                yield(chunk)
            } else if let json = JSONValue.parse(data), let apiError = APIErrorBody.fromObject(json) {
                throw SiliconFlowError.fromAPIError(apiError, status: state.head?.statusCode, head: state.head, endpoint: endpoint, region: region, modelID: model)
            }
        }
        guard !state.sawDone, !state.sawFinishReason else { return }
        if state.chunkCount > 0 {
            throw SiliconFlowError(kind: .streamInterrupted, endpoint: endpoint, traceID: state.head?.traceID, region: region, modelID: model)
        }
        // SSE ではない応答（通常の JSON やエラー本文）
        let raw = Data(parser.rawBody.utf8)
        if let chunk = try? decoder.decode(ChatCompletionChunk.self, from: raw), !chunk.choices.isEmpty {
            state.chunkCount += 1
            yield(chunk)
            return
        }
        guard !raw.isEmpty, let head = state.head else {
            throw SiliconFlowError(kind: .emptyResponse, endpoint: endpoint, httpStatus: state.head?.statusCode, region: region, modelID: model)
        }
        throw describeUndecodable(raw, head: head, endpoint: endpoint, modelID: model, decodingError: nil)
    }

    private func finalError(_ error: Error, state: StreamState, endpoint: String, model: String) -> SiliconFlowError {
        var wrapped = SiliconFlowError.wrap(error, endpoint: endpoint, region: region, modelID: model)
        let networkKinds: Set<FailureKind> = [.connectionFailed, .timedOut, .offline]
        if state.chunkCount > 0, networkKinds.contains(wrapped.kind) {
            wrapped.kind = .streamInterrupted
        }
        if wrapped.traceID == nil { wrapped.traceID = state.head?.traceID }
        return wrapped
    }
}

/// ストリーム受信中の状態
struct StreamState: Sendable {
    var head: HTTPResponseHead?
    var chunkCount = 0
    var sawDone = false
    var sawFinishReason = false
}
