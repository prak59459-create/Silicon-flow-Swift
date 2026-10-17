import XCTest
@testable import SiliconFlowKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClientRequestTests: XCTestCase {
    func testListModelsBuildsAuthorizedRequest() async throws {
        let transport = MockTransport(.json(#"{"object":"list","data":[{"id":"Qwen/Qwen3-8B","object":"model","created":0,"owned_by":""},{"id":"BAAI/bge-m3"}]}"#))
        let client = makeClient(transport, key: "  Bearer sk-abcdefghijklmnopqrstuvwxyz \n")
        let models = try await client.listModels(.subType("chat"))
        XCTAssertEqual(models.map(\.id), ["Qwen/Qwen3-8B", "BAAI/bge-m3"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://api.siliconflow.cn/v1/models?sub_type=chat")
        XCTAssertEqual(request.header("Authorization"), "Bearer sk-abcdefghijklmnopqrstuvwxyz")
        XCTAssertEqual(request.header("Accept"), "application/json")
        XCTAssertNotNil(request.header("User-Agent"))
        XCTAssertNil(request.body)
    }

    func testListModelsSkipsBrokenItems() async throws {
        let transport = MockTransport(.json(#"{"data":[{"id":"ok/model"},{"object":"model"},{"id":42}]}"#))
        let models = try await makeClient(transport).listModels()
        XCTAssertEqual(models.map(\.id), ["ok/model"])
    }

    func testCustomBaseURLAndRegion() async throws {
        let transport = MockTransport(.json(#"{"data":[]}"#))
        var client = makeClient(transport, region: .international)
        XCTAssertEqual(client.configuration.baseURL.host, "api.siliconflow.com")
        client = SiliconFlowClient(
            configuration: ClientConfiguration(region: .china, apiKey: "sk-abcdefghijklmnopqrstuvwxyz", customBaseURL: URL(string: "https://proxy.example.com/v1")),
            transport: transport
        )
        _ = try await client.listModels(.type("audio"))
        XCTAssertEqual(transport.requests.last?.url.absoluteString, "https://proxy.example.com/v1/models?type=audio")
    }

    func testMissingKeyFailsWithoutNetwork() async {
        let transport = MockTransport(.json("{}"))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport, key: " ").listModels() }
        XCTAssertEqual(error?.kind, .missingAPIKey)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testMalformedKeyFailsWithoutNetwork() async {
        let transport = MockTransport(.json("{}"))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport, key: "sk-abc def ghi jkl mno pqr").listModels() }
        XCTAssertEqual(error?.kind, .malformedAPIKey)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testChatRequestEncoding() async throws {
        let transport = MockTransport(.json(#"{"id":"1","model":"Qwen/Qwen3-8B","choices":[{"index":0,"message":{"role":"assistant","content":"こんにちは","reasoning_content":"考え中"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12,"completion_tokens_details":{"reasoning_tokens":3}}}"#))
        let request = ChatCompletionRequest(
            model: "Qwen/Qwen3-8B",
            messages: [ChatMessagePayload(role: .user, text: "hi")],
            stream: true,
            maxTokens: 64,
            temperature: 0.5,
            enableThinking: false,
            stop: ["a", "b", "c", "d", "e"],
            jsonMode: true
        )
        let response = try await makeClient(transport).chat(request)
        XCTAssertEqual(response.primaryContent, "こんにちは")
        XCTAssertEqual(response.primaryReasoning, "考え中")
        XCTAssertEqual(response.usage?.reasoningTokens, 3)
        XCTAssertEqual(response.usage?.effectiveTotal, 12)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.url.path, "/v1/chat/completions")
        XCTAssertEqual(sent.header("Content-Type"), "application/json")
        let json = try XCTUnwrap(JSONValue.parse(try XCTUnwrap(sent.body)))
        XCTAssertEqual(json["stream"], .bool(false), "chat() は常に非ストリーミングで送る")
        XCTAssertEqual(json["max_tokens"]?.intValue, 64)
        XCTAssertEqual(json["enable_thinking"], .bool(false))
        XCTAssertEqual(json["stop"]?.arrayValue?.count, 4, "stop は最大 4 個")
        XCTAssertEqual(json["response_format"]?["type"]?.stringValue, "json_object")
        XCTAssertNil(json["top_p"], "未指定の値は送らない")
        XCTAssertNil(json["thinking_budget"])
        XCTAssertEqual(json["messages"]?.arrayValue?.first?["content"]?.stringValue, "hi")
    }

    func testVisionContentEncoding() throws {
        let payload = ChatMessagePayload(role: .user, content: .parts([.imageURL("data:image/jpeg;base64,AAAA", detail: .auto), .text("これは何？")]))
        let json = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(payload)))
        let parts = try XCTUnwrap(json["content"]?.arrayValue)
        XCTAssertEqual(parts[0]["type"]?.stringValue, "image_url")
        XCTAssertEqual(parts[0]["image_url"]?["url"]?.stringValue, "data:image/jpeg;base64,AAAA")
        XCTAssertEqual(parts[0]["image_url"]?["detail"]?.stringValue, "auto")
        XCTAssertEqual(parts[1]["type"]?.stringValue, "text")
        XCTAssertEqual(parts[1]["text"]?.stringValue, "これは何？")
    }

    func testOtherEndpointsEncodeSnakeCase() throws {
        let image = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(ImageGenerationRequest(model: "m", prompt: "p", negativePrompt: "", imageSize: "1024x1024", seed: 7, numInferenceSteps: 20, guidanceScale: 7.5))))
        XCTAssertEqual(image["image_size"]?.stringValue, "1024x1024")
        XCTAssertEqual(image["num_inference_steps"]?.intValue, 20)
        XCTAssertNil(image["negative_prompt"], "空のネガティブプロンプトは送らない")
        XCTAssertNil(image["batch_size"], "batch_size は 2026-09-30 に廃止された")
        let rerank = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(RerankRequest(model: "m", query: "q", documents: ["a"], topN: 1))))
        XCTAssertEqual(rerank["top_n"]?.intValue, 1)
        XCTAssertEqual(rerank["return_documents"], .bool(true))
        let speech = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(SpeechRequest(model: "m", input: "hello", voice: SpeechRequest.voiceID(model: "m", voice: "alex"), speed: 1.2))))
        XCTAssertEqual(speech["voice"]?.stringValue, "m:alex")
        XCTAssertEqual(speech["response_format"]?.stringValue, "mp3")
        XCTAssertEqual(speech["stream"], .bool(false))
        let embed = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(EmbeddingRequest(model: "m", input: ["a", "b"]))))
        XCTAssertEqual(embed["encoding_format"]?.stringValue, "float")
        let video = try XCTUnwrap(JSONValue.parse(try JSONEncoder().encode(VideoSubmitRequest(model: "m", prompt: "p", imageSize: "1280x720"))))
        XCTAssertEqual(video["image_size"]?.stringValue, "1280x720")
    }
}

final class ClientErrorTests: XCTestCase {
    func testUnauthorizedProducesDiagnosis() async {
        let transport = MockTransport(.json(#"{"code":30014,"data":null,"message":"Token is invalid."}"#, status: 401, headers: ["x-siliconcloud-trace-id": "abc-123"]))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).userInfo() }
        XCTAssertEqual(error?.kind, .invalidAPIKey)
        XCTAssertEqual(error?.httpStatus, 401)
        XCTAssertEqual(error?.apiCode, 30014)
        XCTAssertEqual(error?.traceID, "abc-123")
        XCTAssertEqual(error?.endpoint, "GET /user/info")
        XCTAssertEqual(error?.region, .china)
        XCTAssertEqual(transport.requests.count, 1, "401 は再試行しない")
    }

    func testEmbeddedErrorIn200Response() async {
        let transport = MockTransport(.json(#"{"code":20012,"message":"Model does not exist. Please check it carefully.","data":null}"#))
        let request = ChatCompletionRequest(model: "nope/model", messages: [ChatMessagePayload(role: .user, text: "hi")])
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).chat(request) }
        XCTAssertEqual(error?.kind, .modelNotFound)
        XCTAssertEqual(error?.modelID, "nope/model")
    }

    func testHTMLResponseIsUnexpected() async {
        let transport = MockTransport(.text("<!DOCTYPE html><html><head><title>Hotel WiFi</title></head></html>", status: 200, contentType: "text/html"))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).listModels() }
        XCTAssertEqual(error?.kind, .unexpectedResponse)
        XCTAssertTrue(error?.bodySnippet?.contains("Hotel WiFi") ?? false)
    }

    func testGarbageJSONIsDecodingFailure() async {
        let transport = MockTransport(.json(#"{"unexpected":true}"#))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).listModels() }
        XCTAssertEqual(error?.kind, .decodingFailed)
    }

    func testEmptyBodyIsEmptyResponse() async {
        let transport = MockTransport(.json(""))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).listModels() }
        XCTAssertEqual(error?.kind, .emptyResponse)
    }

    func testGETRetriesOnOverloadThenSucceeds() async throws {
        let transport = MockTransport { _, count in
            count < 3 ? .json(#"{"code":50505,"message":"Model service overloaded."}"#, status: 503) : .json(#"{"data":[{"id":"a/b"}]}"#)
        }
        let models = try await makeClient(transport).listModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testGETGivesUpAfterMaxRetries() async {
        let transport = MockTransport(.json("", status: 504))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport, retry: RetryPolicy(maxRetries: 2)).listModels() }
        XCTAssertEqual(error?.kind, .gatewayTimeout)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testPOSTIsNotRetried() async {
        let transport = MockTransport(.json(#"{"message":"overloaded"}"#, status: 503))
        let request = ChatCompletionRequest(model: "a/b", messages: [ChatMessagePayload(role: .user, text: "hi")])
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport).chat(request) }
        XCTAssertEqual(error?.kind, .overloaded)
        XCTAssertEqual(transport.requests.count, 1, "課金が二重にならないよう POST は自動再試行しない")
    }

    func testNetworkErrorsAreClassified() async {
        let offline = MockTransport(.failure(URLError(.notConnectedToInternet)))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(offline, retry: .none).listModels() }
        XCTAssertEqual(error?.kind, .offline)
        XCTAssertEqual(error?.endpoint, "GET /models")

        let dns = MockTransport(.failure(URLError(.cannotFindHost)))
        let dnsError = await assertThrowsSiliconFlowError { try await self.makeClient(dns, retry: .none).userInfo() }
        XCTAssertEqual(dnsError?.kind, .dnsFailure)
    }

    func testRateLimitCarriesRetryAfter() async {
        let transport = MockTransport(.json(#"{"message":"Request was rejected due to rate limiting. Details:RPM limit reached."}"#, status: 429, headers: ["Retry-After": "7"]))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(transport, retry: .none).listModels() }
        XCTAssertEqual(error?.kind, .rateLimited)
        XCTAssertEqual(error?.retryAfter, 7)
        XCTAssertTrue(error?.diagnosis.cause.contains("RPM") ?? false)
    }

    func testUserInfoParsesStringBalances() async throws {
        let transport = MockTransport(.json(#"{"code":20000,"message":"OK","status":true,"data":{"id":"u1","name":"","image":"","email":"","isAdmin":false,"balance":"0.88","status":"normal","introduction":"","role":"","chargeBalance":"88.00","totalBalance":"88.88"}}"#))
        let info = try await makeClient(transport).userInfo()
        XCTAssertEqual(info.id, "u1")
        XCTAssertNil(info.name, "空文字は nil にする")
        XCTAssertEqual(info.balance, 0.88)
        XCTAssertEqual(info.chargeBalance, 88)
        XCTAssertEqual(info.totalBalance, 88.88)
        XCTAssertTrue(info.isNormalStatus)
    }

    func testUserInfoComputesTotalWhenMissing() {
        let info = UserInfo(balance: 1, chargeBalance: 2)
        XCTAssertEqual(info.effectiveTotal, 3)
        XCTAssertFalse(UserInfo(status: "frozen").isNormalStatus)
    }

    func testSpeechReturnsAudioAndRejectsJSON() async throws {
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let ok = MockTransport(MockTransport.Reply(status: 200, headers: ["Content-Type": "audio/mpeg"], body: audio))
        let data = try await makeClient(ok).speech(SpeechRequest(model: "m", input: "hi", voice: nil))
        XCTAssertEqual(data, audio)

        let bad = MockTransport(.json(#"{"code":20012,"message":"Model does not exist."}"#))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(bad).speech(SpeechRequest(model: "m", input: "hi", voice: nil)) }
        XCTAssertEqual(error?.kind, .modelNotFound)
    }

    func testTranscriptionSendsMultipart() async throws {
        let transport = MockTransport(.json(#"{"text":"こんにちは"}"#))
        let result = try await makeClient(transport).transcribe(audio: Data([1, 2, 3]), fileName: "a.mp3", mimeType: "audio/mpeg", model: "FunAudioLLM/SenseVoiceSmall")
        XCTAssertEqual(result.text, "こんにちは")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.header("Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = String(decoding: try XCTUnwrap(request.body), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("FunAudioLLM/SenseVoiceSmall"))
        XCTAssertTrue(body.contains("filename=\"a.mp3\""))
    }

    func testProbeReachabilityDoesNotSendKey() async throws {
        let transport = MockTransport(.json(#"{"code":30014,"message":"Token is invalid."}"#, status: 401))
        let head = try await makeClient(transport).probeReachability()
        XCTAssertEqual(head.statusCode, 401)
        XCTAssertNil(transport.requests.first?.header("Authorization"))
    }

    func testMediaResponses() async throws {
        let image = MockTransport(.json(#"{"images":[{"url":"https://example.com/a.png"}],"timings":{"inference":1.5},"seed":42}"#))
        let generated = try await makeClient(image).generateImage(ImageGenerationRequest(model: "m", prompt: "cat"))
        XCTAssertEqual(generated.imageURLs.map(\.absoluteString), ["https://example.com/a.png"])
        XCTAssertEqual(generated.seed, 42)

        let emptyImage = MockTransport(.json(#"{"images":[]}"#))
        let error = await assertThrowsSiliconFlowError { try await self.makeClient(emptyImage).generateImage(ImageGenerationRequest(model: "m", prompt: "cat")) }
        XCTAssertEqual(error?.kind, .emptyResponse)

        let embed = MockTransport(.json(#"{"model":"m","data":[{"index":1,"embedding":[0,1]},{"index":0,"embedding":[1,0]}],"usage":{"prompt_tokens":4,"total_tokens":4}}"#))
        let vectors = try await makeClient(embed).embeddings(EmbeddingRequest(model: "m", input: ["a", "b"])).vectors
        XCTAssertEqual(vectors, [[1, 0], [0, 1]], "index 順に並べ直す")

        let rerank = MockTransport(.json(#"{"id":"r","results":[{"index":0,"relevance_score":0.1,"document":{"text":"a"}},{"index":1,"relevance_score":0.9}],"tokens":{"input_tokens":10}}"#))
        let ranked = try await makeClient(rerank).rerank(RerankRequest(model: "m", query: "q", documents: ["a", "b"])).ranked
        XCTAssertEqual(ranked.map(\.index), [1, 0])

        let submit = MockTransport(.json(#"{"requestId":"req-1"}"#))
        let submitted = try await makeClient(submit).submitVideo(VideoSubmitRequest(model: "m", prompt: "p"))
        XCTAssertEqual(submitted.requestID, "req-1")
        let status = MockTransport(.json(#"{"status":"Succeed","reason":"","results":{"videos":[{"url":"https://example.com/v.mp4"}],"timings":{"inference":30},"seed":1}}"#))
        let video = try await makeClient(status).videoStatus(requestID: "req-1")
        XCTAssertEqual(video.status, .succeed)
        XCTAssertTrue(video.status.isFinished)
        XCTAssertEqual(video.videoURLs.count, 1)
        let body = try XCTUnwrap(JSONValue.parse(try XCTUnwrap(status.requests.first?.body)))
        XCTAssertEqual(body["requestId"]?.stringValue, "req-1")
    }
}
