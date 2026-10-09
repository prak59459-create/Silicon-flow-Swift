import Foundation

extension SiliconFlowClient {
    /// 利用可能なモデル一覧（`GET /models`）
    public func listModels(_ filter: ModelListFilter = .all) async throws -> [RemoteModel] {
        let request = try makeRequest(.get, path: "models", query: filter.queryItems)
        let response = try await sendDecodable(
            ModelListResponse.self,
            request: request,
            endpoint: Self.label(.get, "models"),
            retry: retryPolicy
        )
        return response.data
    }

    /// アカウント情報・残高（`GET /user/info`）
    public func userInfo() async throws -> UserInfo {
        let endpoint = Self.label(.get, "user/info")
        let request = try makeRequest(.get, path: "user/info")
        let (data, head) = try await send(request, endpoint: endpoint, modelID: nil, retry: retryPolicy)
        if let info = UserInfo.parse(data) { return info }
        throw describeUndecodable(data, head: head, endpoint: endpoint, modelID: nil, decodingError: nil)
    }

    /// チャット（通常応答）
    public func chat(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        var body = request
        body.stream = false
        let endpoint = Self.label(.post, "chat/completions")
        let http = try makeRequest(.post, path: "chat/completions", body: try encodeJSON(body))
        let (data, head) = try await send(http, endpoint: endpoint, modelID: request.model, retry: .none)
        let response = try decode(ChatCompletionResponse.self, from: data, head: head, endpoint: endpoint, modelID: request.model)
        if response.choices.isEmpty {
            throw emptyResultError(data, head: head, endpoint: endpoint, modelID: request.model)
        }
        return response
    }

    /// 画像生成
    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResponse {
        let endpoint = Self.label(.post, "images/generations")
        let http = try makeRequest(.post, path: "images/generations", body: try encodeJSON(request))
        let (data, head) = try await send(http, endpoint: endpoint, modelID: request.model, retry: .none)
        let response = try decode(ImageGenerationResponse.self, from: data, head: head, endpoint: endpoint, modelID: request.model)
        if response.images.isEmpty {
            throw emptyResultError(data, head: head, endpoint: endpoint, modelID: request.model)
        }
        return response
    }

    /// 埋め込みベクトル
    public func embeddings(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
        let http = try makeRequest(.post, path: "embeddings", body: try encodeJSON(request))
        return try await sendDecodable(EmbeddingResponse.self, request: http, endpoint: Self.label(.post, "embeddings"), modelID: request.model, retry: .none)
    }

    /// リランク
    public func rerank(_ request: RerankRequest) async throws -> RerankResponse {
        let http = try makeRequest(.post, path: "rerank", body: try encodeJSON(request))
        return try await sendDecodable(RerankResponse.self, request: http, endpoint: Self.label(.post, "rerank"), modelID: request.model, retry: .none)
    }

    /// 音声合成。音声データ（mp3 等）を返します。
    public func speech(_ request: SpeechRequest) async throws -> Data {
        let endpoint = Self.label(.post, "audio/speech")
        let http = try makeRequest(.post, path: "audio/speech", body: try encodeJSON(request), accept: "audio/*, application/json")
        let (data, head) = try await send(http, endpoint: endpoint, modelID: request.model, retry: .none)
        let contentType = head.contentType ?? ""
        if contentType.contains("json") || contentType.contains("text/") || data.isEmpty {
            throw describeUndecodable(data, head: head, endpoint: endpoint, modelID: request.model, decodingError: nil)
        }
        return data
    }

    /// 音声認識（`multipart/form-data` でファイルを送ります）
    public func transcribe(audio: Data, fileName: String, mimeType: String, model: String) async throws -> TranscriptionResponse {
        var form = MultipartFormData()
        form.addField(name: "model", value: model)
        form.addFile(name: "file", fileName: fileName, mimeType: mimeType, data: audio)
        let http = try makeRequest(.post, path: "audio/transcriptions", body: form.finalized(), contentType: form.contentType)
        return try await sendDecodable(TranscriptionResponse.self, request: http, endpoint: Self.label(.post, "audio/transcriptions"), modelID: model, retry: .none)
    }

    /// 動画生成の受付
    public func submitVideo(_ request: VideoSubmitRequest) async throws -> VideoSubmitResponse {
        let http = try makeRequest(.post, path: "video/submit", body: try encodeJSON(request))
        return try await sendDecodable(VideoSubmitResponse.self, request: http, endpoint: Self.label(.post, "video/submit"), modelID: request.model, retry: .none)
    }

    /// 動画生成の進み具合（何度呼んでも料金はかからないので再試行します）
    public func videoStatus(requestID: String) async throws -> VideoStatusResponse {
        struct Body: Encodable { let requestId: String }
        let http = try makeRequest(.post, path: "video/status", body: try encodeJSON(Body(requestId: requestID)))
        return try await sendDecodable(VideoStatusResponse.self, request: http, endpoint: Self.label(.post, "video/status"), retry: retryPolicy)
    }

    /// 接続確認用：認証なしで API サーバーに届くかだけを調べます（401 が返れば到達できている）。
    public func probeReachability() async throws -> HTTPResponseHead {
        let url = configuration.baseURL.appendingPathComponent("models")
        let request = HTTPRequest(method: .get, url: url, headers: ["Accept": "application/json", "User-Agent": configuration.userAgent], timeout: 20)
        do {
            let (_, head) = try await transport.send(request)
            return head
        } catch {
            throw SiliconFlowError.wrap(error, endpoint: Self.label(.get, "models"), region: region)
        }
    }
}
