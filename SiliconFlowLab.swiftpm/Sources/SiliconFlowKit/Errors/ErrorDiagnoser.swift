import Foundation

/// SiliconFlowError から日本語の診断（原因と直し方）を組み立てます。
public enum ErrorDiagnoser {
    public static func diagnose(_ error: SiliconFlowError) -> ErrorDiagnosis {
        let context = DiagnosisContext(error: error)
        switch error.kind {
        case .missingAPIKey, .malformedAPIKey, .invalidAPIKey, .invalidBaseURL:
            return AccountDiagnoses.credentials(context)
        case .forbidden, .realNameRequired, .insufficientBalance, .modelAccessDenied:
            return AccountDiagnoses.permission(context)
        case .modelNotFound, .modelDeprecated, .endpointNotFound:
            return RequestDiagnoses.notFound(context)
        case .endpointRetired:
            return RequestDiagnoses.retiredEndpoint(context)
        case .invalidRequest, .contextTooLong, .unsupportedParameter, .payloadTooLarge, .contentFiltered:
            return RequestDiagnoses.badRequest(context)
        case .rateLimited, .serverError, .badGateway, .overloaded, .gatewayTimeout:
            return ServerDiagnoses.server(context)
        case .offline, .timedOut, .dnsFailure, .connectionFailed, .tlsFailure, .cancelled:
            return NetworkDiagnoses.network(context)
        case .unexpectedResponse, .decodingFailed, .streamInterrupted, .emptyResponse, .unknown:
            return NetworkDiagnoses.response(context)
        }
    }
}

/// 診断文の組み立てに使う共通情報
struct DiagnosisContext {
    let error: SiliconFlowError
    let region: APIRegion

    init(error: SiliconFlowError) {
        self.error = error
        self.region = error.region ?? .china
    }

    var kind: FailureKind { error.kind }

    /// サーバーのメッセージを引用した一文（無ければ空）
    var quotedServerMessage: String {
        guard let message = error.serverMessage, !message.isEmpty else { return "" }
        return "\nサーバーからのメッセージ: 「\(TextSanitizer.snippet(message, limit: 200))」"
    }

    var statusLabel: String {
        var parts: [String] = []
        if let status = error.httpStatus { parts.append("HTTP \(status)") }
        if let code = error.apiCode { parts.append("コード \(code)") }
        return parts.isEmpty ? "" : "（" + parts.joined(separator: " / ") + "）"
    }

    var modelLabel: String {
        guard let model = error.modelID else { return "このモデル" }
        return "「\(model)」"
    }

    var openKeysPage: DiagnosisAction {
        .openURL(title: "API キーのページを開く", url: region.apiKeysURL)
    }

    var openConsole: DiagnosisAction {
        .openURL(title: "コンソールを開く", url: region.consoleURL)
    }

    var openModelsPage: DiagnosisAction {
        .openURL(title: "公式のモデル一覧を開く", url: region.modelsPageURL)
    }

    var openErrorDocs: DiagnosisAction {
        .openURL(title: "エラーコードの説明を開く", url: region.errorDocsURL)
    }

    var openReleaseNotes: DiagnosisAction {
        .openURL(title: "公式のお知らせを開く", url: region.releaseNotesURL)
    }

    /// 例: 「GET /user/info」
    var endpointLabel: String {
        guard let endpoint = error.endpoint, !endpoint.isEmpty else { return "この API" }
        return "「\(endpoint)」"
    }

    /// 残高照会 API（`GET /user/info`）の失敗か
    var isBalanceEndpoint: Bool {
        (error.endpoint ?? "").contains("user/info")
    }

    var isChatEndpoint: Bool {
        (error.endpoint ?? "").contains("/chat/completions")
    }
}
