import XCTest
@testable import SiliconFlowKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class LineAndSSEParserTests: XCTestCase {
    func testLineSplitterHandlesCRLFAndEmptyLines() {
        XCTAssertEqual(LineSplitter.lines(in: Data("a\r\n\r\nb\nc".utf8)), ["a", "", "b", "c"])
    }

    func testLineSplitterKeepsMultibyteCharactersIntact() {
        var splitter = LineSplitter()
        let bytes = Array("日本語\n".utf8)
        var lines: [String] = []
        for byte in bytes {
            if let line = splitter.append(byte) { lines.append(line) }
        }
        XCTAssertEqual(lines, ["日本語"])
        XCTAssertNil(splitter.finish())
    }

    func testSSEParser() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(line: ": keep-alive"))
        XCTAssertNil(parser.consume(line: "event: message"))
        XCTAssertEqual(parser.consume(line: "data: {\"a\":1}"), SSEEvent(event: "message", data: "{\"a\":1}"))
        XCTAssertNil(parser.consume(line: ""))
        XCTAssertEqual(parser.consume(line: "data:{\"b\":2}"), SSEEvent(data: "{\"b\":2}"))
        XCTAssertTrue(parser.consume(line: "data: [DONE]")?.isDone ?? false)
        XCTAssertEqual(parser.eventCount, 3)
    }

    func testSSEParserCollectsRawLines() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(line: #"{"code":30014,"message":"Token is invalid."}"#))
        XCTAssertNil(parser.consume(line: "plain text"))
        XCTAssertEqual(parser.rawLines.count, 2)
        XCTAssertTrue(parser.rawBody.contains("30014"))
    }
}

final class StreamingChatTests: XCTestCase {
    private let request = ChatCompletionRequest(model: "deepseek-ai/DeepSeek-R1", messages: [ChatMessagePayload(role: .user, text: "1+1?")])

    private func collect(_ client: SiliconFlowClient) async throws -> [ChatCompletionChunk] {
        var chunks: [ChatCompletionChunk] = []
        for try await chunk in client.streamChat(request) { chunks.append(chunk) }
        return chunks
    }

    func testStreamsReasoningContentAndUsage() async throws {
        let transport = MockTransport(.sse([
            #"data: {"id":"1","model":"deepseek-ai/DeepSeek-R1","choices":[{"index":0,"delta":{"role":"assistant","content":null,"reasoning_content":"まず"}}]}"#,
            "",
            #"data: {"id":"1","choices":[{"index":0,"delta":{"content":null,"reasoning_content":"考える"}}]}"#,
            "",
            #"data: {"id":"1","choices":[{"index":0,"delta":{"content":"答えは"}}]}"#,
            #"data: {"id":"1","choices":[{"index":0,"delta":{"content":"2です"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}"#,
            "data: [DONE]",
        ]))
        let chunks = try await collect(makeClient(transport))
        var accumulator = GenerationAccumulator(startedAt: 0)
        for (index, chunk) in chunks.enumerated() { accumulator.apply(chunk, at: Double(index + 1)) }
        accumulator.finish(at: 10)
        XCTAssertEqual(accumulator.reasoning, "まず考える")
        XCTAssertEqual(accumulator.content, "答えは2です")
        XCTAssertEqual(accumulator.finishReason, "stop")
        XCTAssertEqual(accumulator.usage?.totalTokens, 30)
        XCTAssertEqual(accumulator.model, "deepseek-ai/DeepSeek-R1")
        XCTAssertEqual(accumulator.metrics.timeToFirstToken, 1)
        XCTAssertEqual(accumulator.metrics.reasoningDuration, 2)
        XCTAssertEqual(accumulator.metrics.totalDuration, 10)
        XCTAssertEqual(accumulator.metrics.tokensPerSecond(completionTokens: 20) ?? 0, 20.0 / 9.0, accuracy: 0.0001)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.header("Accept"), "text/event-stream")
        XCTAssertEqual(JSONValue.parse(try XCTUnwrap(sent.body))?["stream"], .bool(true))
    }

    func testErrorJSONInsideStream() async {
        let transport = MockTransport(.sse([
            #"data: {"choices":[{"delta":{"content":"途中"}}]}"#,
            #"data: {"code":50505,"message":"Model service overloaded. Please try again later."}"#,
        ]))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .overloaded)
        XCTAssertEqual(error?.modelID, "deepseek-ai/DeepSeek-R1")
    }

    func testStreamWithoutDoneIsInterrupted() async {
        let transport = MockTransport(.sse([#"data: {"choices":[{"delta":{"content":"途中まで"}}]}"#]))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .streamInterrupted)
    }

    func testFinishReasonWithoutDoneIsAccepted() async throws {
        let transport = MockTransport(.sse([#"data: {"choices":[{"delta":{"content":"完了"},"finish_reason":"stop"}]}"#]))
        let chunks = try await collect(makeClient(transport))
        XCTAssertEqual(chunks.count, 1)
    }

    func testConnectionLossMidStreamBecomesInterrupted() async {
        let transport = MockTransport(.sse([#"data: {"choices":[{"delta":{"content":"a"}}]}"#], streamError: URLError(.networkConnectionLost)))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .streamInterrupted)
    }

    func testConnectionLossBeforeAnyChunkIsConnectionFailure() async {
        let transport = MockTransport(.sse([], streamError: URLError(.networkConnectionLost)))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .connectionFailed)
    }

    func testNonSSEJSONResponseIsAccepted() async throws {
        let transport = MockTransport(.json(#"{"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":"通常応答"},"finish_reason":"stop"}]}"#))
        let chunks = try await collect(makeClient(transport))
        XCTAssertEqual(chunks.first?.primaryContent, "通常応答")
    }

    func testNon2xxStreamParsesErrorBody() async {
        let transport = MockTransport(.json(#"{"code":20012,"message":"Model does not exist. Please check it carefully.","data":null}"#, status: 400))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .modelNotFound)
        XCTAssertEqual(error?.httpStatus, 400)
    }

    func testEmptyStreamIsEmptyResponse() async {
        let transport = MockTransport(.sse([]))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .emptyResponse)
    }

    func testTransportFailureBeforeResponse() async {
        let transport = MockTransport(.failure(URLError(.timedOut)))
        let error = await assertThrowsSiliconFlowError { try await self.collect(self.makeClient(transport)) }
        XCTAssertEqual(error?.kind, .timedOut)
    }

    func testCancellationStopsStream() async throws {
        let transport = MockTransport(.sse((0..<50).map { #"data: {"choices":[{"delta":{"content":"\#($0)"}}]}"# } + ["data: [DONE]"]))
        let client = makeClient(transport)
        let request = self.request
        let task = Task { () -> Int in
            var count = 0
            for try await _ in client.streamChat(request) {
                count += 1
                if count == 3 { break }
            }
            return count
        }
        let count = try await task.value
        XCTAssertEqual(count, 3)
    }
}

final class GenerationAccumulatorTests: XCTestCase {
    func testTruncationAndFilterFlags() {
        var accumulator = GenerationAccumulator(startedAt: 0)
        accumulator.apply(ChatCompletionChunk(choices: [ChatChoice(delta: ChatMessageDelta(content: "x"), finishReason: "length")]), at: 1)
        XCTAssertTrue(accumulator.wasTruncated)
        XCTAssertFalse(accumulator.wasFiltered)
    }

    func testTokenEstimateWithoutUsage() {
        var accumulator = GenerationAccumulator(startedAt: 0)
        accumulator.apply(ChatCompletionChunk(choices: [ChatChoice(delta: ChatMessageDelta(content: "abcdefgh日本"))]), at: 1)
        XCTAssertEqual(accumulator.completionTokensEstimate, 4)
        XCTAssertEqual(TokenEstimator.estimate(""), 0)
    }

    func testMetricsWithoutTokens() {
        let metrics = GenerationMetrics(startedAt: 5)
        XCTAssertNil(metrics.timeToFirstToken)
        XCTAssertNil(metrics.tokensPerSecond(completionTokens: 10))
    }
}
