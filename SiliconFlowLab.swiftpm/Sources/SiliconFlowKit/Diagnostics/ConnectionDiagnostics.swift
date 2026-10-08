import Foundation

/// 接続診断の各ステップ
public enum DiagnosticStep: String, CaseIterable, Sendable, Identifiable {
    case keyFormat
    case reachability
    case authentication
    case modelList
    case testChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyFormat: return "API キーの形式"
        case .reachability: return "サーバーへの接続"
        case .authentication: return "API キーの認証と残高"
        case .modelList: return "モデル一覧の取得"
        case .testChat: return "テスト送信（無料モデル）"
        }
    }

    public var systemImage: String {
        switch self {
        case .keyFormat: return "key"
        case .reachability: return "network"
        case .authentication: return "person.badge.key"
        case .modelList: return "list.bullet.rectangle"
        case .testChat: return "paperplane"
        }
    }
}

/// ステップの結果
public enum DiagnosticOutcome: Sendable, Equatable {
    case passed(String)
    case warning(String)
    case failed(SiliconFlowError)
    case skipped(String)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .passed(let text), .warning(let text), .skipped(let text): return text
        case .failed(let error): return error.diagnosis.title
        }
    }
}

/// 接続を段階的に調べて、どこで失敗しているかを特定します。
public struct ConnectionDiagnostics: Sendable {
    public let client: SiliconFlowClient

    public init(client: SiliconFlowClient) {
        self.client = client
    }

    public func run(_ step: DiagnosticStep, testModel: String?) async -> DiagnosticOutcome {
        switch step {
        case .keyFormat: return checkKeyFormat()
        case .reachability: return await checkReachability()
        case .authentication: return await checkAuthentication()
        case .modelList: return await checkModelList()
        case .testChat: return await checkTestChat(model: testModel)
        }
    }

    func checkKeyFormat() -> DiagnosticOutcome {
        let result = APIKeyValidator.validate(client.configuration.apiKey)
        if result.issues.contains(.empty) {
            return .failed(SiliconFlowError(kind: .missingAPIKey, region: client.region))
        }
        if !result.isUsable {
            return .failed(SiliconFlowError(kind: .malformedAPIKey, underlying: result.issues.map(\.message).joined(separator: " "), region: client.region))
        }
        if !result.warnings.isEmpty {
            return .warning(result.warnings.map(\.message).joined(separator: " "))
        }
        return .passed("形式は正常です（\(TextSanitizer.masked(result.sanitizedKey))）")
    }

    func checkReachability() async -> DiagnosticOutcome {
        let host = client.configuration.baseURL.host ?? client.region.host
        do {
            let head = try await client.probeReachability()
            if head.statusCode == 401 || head.isSuccess {
                return .passed("\(host) に接続できました（HTTPS 正常）")
            }
            if head.contentType?.contains("text/html") == true {
                return .failed(SiliconFlowError(kind: .unexpectedResponse, endpoint: "GET /models", httpStatus: head.statusCode, region: client.region))
            }
            return .warning("\(host) に接続できましたが、HTTP \(head.statusCode) が返りました")
        } catch {
            return .failed(SiliconFlowError.wrap(error, region: client.region))
        }
    }

    func checkAuthentication() async -> DiagnosticOutcome {
        do {
            let info = try await client.userInfo()
            let currency = client.region.currency
            var text = "認証に成功しました"
            if let total = info.effectiveTotal {
                text += "。残高 \(currency.format(total))"
                if let charge = info.chargeBalance { text += "（うちチャージ残高 \(currency.format(charge))）" }
            }
            if !info.isNormalStatus {
                return .warning(text + "。ただしアカウントの状態が「\(info.status ?? "")」です")
            }
            if let total = info.effectiveTotal, total <= 0 {
                return .warning(text + "。残高が 0 のため、無料モデルしか使えません")
            }
            return .passed(text)
        } catch {
            return .failed(SiliconFlowError.wrap(error, region: client.region))
        }
    }

    func checkModelList() async -> DiagnosticOutcome {
        do {
            let models = try await client.listModels()
            if models.isEmpty { return .warning("モデル一覧が空でした") }
            return .passed("\(models.count) 個のモデルが使えます")
        } catch {
            return .failed(SiliconFlowError.wrap(error, region: client.region))
        }
    }

    func checkTestChat(model: String?) async -> DiagnosticOutcome {
        guard let model else { return .skipped("無料のチャットモデルが見つからないため省略しました") }
        let request = ChatCompletionRequest(
            model: model,
            messages: [ChatMessagePayload(role: .user, text: "Reply with the single word: OK")],
            stream: false,
            maxTokens: 16,
            temperature: 0
        )
        do {
            let response = try await client.chat(request)
            let reply = TextSanitizer.snippet(response.primaryContent ?? response.primaryReasoning ?? "", limit: 40)
            return .passed("\(ModelClassifier.shortName(of: model)) が応答しました: 「\(reply)」")
        } catch {
            return .failed(SiliconFlowError.wrap(error, region: client.region, modelID: model))
        }
    }

    /// 診断用の無料チャットモデルを選びます（小さく速いものを優先）。
    public static func preferredTestModel(from models: [ModelDescriptor]) -> String? {
        let candidates: [ModelDescriptor] = models.filter(isTestCandidate)
        let free: [ModelDescriptor] = candidates.filter(\.isFree).sorted(by: isSmaller)
        if let pick = free.first { return pick.id }
        let known: [String] = ["Qwen/Qwen3-8B", "Qwen/Qwen2.5-7B-Instruct", "THUDM/GLM-4-9B-0414", "THUDM/glm-4-9b-chat"]
        let available = Set(candidates.map(\.id))
        return known.first { available.contains($0) }
    }

    // 型推論の負荷を下げるため、クロージャではなく型の明示された関数にしています
    private static func isTestCandidate(_ model: ModelDescriptor) -> Bool {
        model.category == .chat && model.isListedByAPI && !model.isPro
    }

    private static func sizeForSorting(_ model: ModelDescriptor) -> Double {
        model.parameters?.totalB ?? Double.greatestFiniteMagnitude
    }

    private static func isSmaller(_ lhs: ModelDescriptor, _ rhs: ModelDescriptor) -> Bool {
        sizeForSorting(lhs) < sizeForSorting(rhs)
    }
}

/// API キーがどちらのリージョンのものかを調べます。
public enum RegionDetector {
    public struct Result: Sendable, Equatable {
        public var region: APIRegion
        public var userInfo: UserInfo
    }

    /// 両方のリージョンで `GET /user/info` を試し、認証できた方を返します（優先リージョンを先に判定）。
    public static func detect(
        apiKey: String,
        preferred: APIRegion,
        transport: HTTPTransport = SharedTransport.default
    ) async -> (Result?, [APIRegion: SiliconFlowError]) {
        var errors: [APIRegion: SiliconFlowError] = [:]
        let order = [preferred, preferred.other]
        let outcomes = await withTaskGroup(of: (APIRegion, Swift.Result<UserInfo, SiliconFlowError>).self) { group in
            for region in order {
                group.addTask {
                    var client = SiliconFlowClient(configuration: ClientConfiguration(region: region, apiKey: apiKey, requestTimeout: 20), transport: transport)
                    client.retryPolicy = .none
                    do {
                        return (region, .success(try await client.userInfo()))
                    } catch {
                        return (region, .failure(SiliconFlowError.wrap(error, region: region)))
                    }
                }
            }
            var collected: [APIRegion: Swift.Result<UserInfo, SiliconFlowError>] = [:]
            for await (region, outcome) in group { collected[region] = outcome }
            return collected
        }
        for region in order {
            switch outcomes[region] {
            case .success(let info)?:
                return (Result(region: region, userInfo: info), errors)
            case .failure(let error)?:
                errors[region] = error
            case nil:
                break
            }
        }
        return (nil, errors)
    }
}
