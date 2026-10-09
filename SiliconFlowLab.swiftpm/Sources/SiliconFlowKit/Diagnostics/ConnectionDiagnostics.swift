import Foundation

/// 接続診断の各ステップ
public enum DiagnosticStep: String, CaseIterable, Sendable, Identifiable {
    case keyFormat
    case reachability
    /// `GET /models` を API キー付きで呼んで認証を確かめます（モデル一覧の取得も兼ねます）
    case authentication
    /// 残高（参考）。残高 API は提供終了している場合があり、失敗しても問題として数えません
    case balance
    case testChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyFormat: return "API キーの形式"
        case .reachability: return "サーバーへの接続"
        case .authentication: return "API キーの認証とモデル一覧"
        case .balance: return "残高（参考）"
        case .testChat: return "テスト送信（無料モデル）"
        }
    }

    public var systemImage: String {
        switch self {
        case .keyFormat: return "key"
        case .reachability: return "network"
        case .authentication: return "person.badge.key"
        case .balance: return "creditcard"
        case .testChat: return "paperplane"
        }
    }

    /// 失敗したら後の項目も確実に失敗する項目か
    public var blocksLaterSteps: Bool {
        switch self {
        case .keyFormat, .reachability, .authentication: return true
        case .balance, .testChat: return false
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
        case .balance: return await checkBalance()
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

    /// 認証は残高 API ではなく `GET /models` で確かめます（残高 API は 2026-08-14 に中国版で停止）。
    func checkAuthentication() async -> DiagnosticOutcome {
        do {
            let models = try await client.listModels()
            if models.isEmpty { return .warning("認証に成功しましたが、使えるモデルが 0 個でした") }
            return .passed("認証に成功しました。\(models.count) 個のモデルが使えます")
        } catch {
            return .failed(SiliconFlowError.wrap(error, region: client.region))
        }
    }

    /// 残高は参考情報です。取れなくても失敗にはしません。
    func checkBalance() async -> DiagnosticOutcome {
        switch await client.lookUpBalance() {
        case .available(let info):
            return Self.describe(info, currency: client.region.currency)
        case .unsupported:
            return .skipped("残高照会 API（GET /user/info）は提供終了しました。残高と代金券はコンソールで確認してください（キーや設定の問題ではありません）")
        case .failed(let error):
            if error.isCancellation { return .skipped("中止しました") }
            return .warning("残高を取得できませんでした（\(error.diagnosis.title)）。モデルの利用には影響しません")
        }
    }

    static func describe(_ info: UserInfo, currency: Currency) -> DiagnosticOutcome {
        guard let total = info.effectiveTotal else {
            return .skipped("残高の情報が含まれていませんでした。コンソールで確認してください")
        }
        var text = "残高 \(currency.format(total))"
        if let charge = info.chargeBalance { text += "（うちチャージ残高 \(currency.format(charge))）" }
        text += "。代金券は含まれない場合があります"
        if !info.isNormalStatus {
            return .warning(text + "。アカウントの状態が「\(info.status ?? "")」です")
        }
        if total < 0 {
            return .warning(text + "。残高がマイナス（未払い）のため、チャージするまで API を使えない場合があります")
        }
        if total == 0 {
            return .warning(text + "。残高が 0 です。無料モデルは使えますが、有料モデルには代金券かチャージが必要です")
        }
        return .passed(text)
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
