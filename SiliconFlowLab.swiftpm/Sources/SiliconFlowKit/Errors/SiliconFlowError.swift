import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// アプリ内のすべての失敗をこの型にまとめます。
/// `diagnosis` で「なぜ失敗したか・どうすれば直るか」を取得できます。
public struct SiliconFlowError: Error, Sendable, Equatable, LocalizedError {
    public var kind: FailureKind
    /// 例: "POST /chat/completions"
    public var endpoint: String?
    public var httpStatus: Int?
    public var apiCode: Int?
    public var serverMessage: String?
    public var traceID: String?
    public var retryAfter: TimeInterval?
    public var underlying: String?
    public var region: APIRegion?
    public var modelID: String?
    public var bodySnippet: String?

    public init(
        kind: FailureKind,
        endpoint: String? = nil,
        httpStatus: Int? = nil,
        apiCode: Int? = nil,
        serverMessage: String? = nil,
        traceID: String? = nil,
        retryAfter: TimeInterval? = nil,
        underlying: String? = nil,
        region: APIRegion? = nil,
        modelID: String? = nil,
        bodySnippet: String? = nil
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.httpStatus = httpStatus
        self.apiCode = apiCode
        self.serverMessage = serverMessage
        self.traceID = traceID
        self.retryAfter = retryAfter
        self.underlying = underlying
        self.region = region
        self.modelID = modelID
        self.bodySnippet = bodySnippet
    }

    public var diagnosis: ErrorDiagnosis { ErrorDiagnoser.diagnose(self) }

    public var errorDescription: String? { diagnosis.title }

    public var isCancellation: Bool { kind == .cancelled }

    /// HTTP エラー応答から作ります。
    public static func http(
        status: Int,
        body: Data,
        head: HTTPResponseHead?,
        endpoint: String?,
        region: APIRegion?,
        modelID: String? = nil
    ) -> SiliconFlowError {
        let parsed = APIErrorBody.parse(body)
        return fromAPIError(parsed, status: status, head: head, endpoint: endpoint, region: region, modelID: modelID)
    }

    /// 解析済みのエラー本文から作ります（200 応答に埋め込まれたエラーにも使います）。
    public static func fromAPIError(
        _ body: APIErrorBody,
        status: Int?,
        head: HTTPResponseHead?,
        endpoint: String?,
        region: APIRegion?,
        modelID: String? = nil
    ) -> SiliconFlowError {
        let kind = FailureClassifier.classify(status: status, body: body, endpoint: endpoint)
        return SiliconFlowError(
            kind: kind,
            endpoint: endpoint,
            httpStatus: status,
            apiCode: body.code,
            serverMessage: body.message,
            traceID: head?.traceID,
            retryAfter: head?.retryAfter,
            region: region,
            modelID: modelID,
            bodySnippet: body.rawSnippet
        )
    }

    /// 任意のエラーを SiliconFlowError に変換します。
    public static func wrap(_ error: Error, endpoint: String? = nil, region: APIRegion? = nil, modelID: String? = nil) -> SiliconFlowError {
        if var known = error as? SiliconFlowError {
            if known.endpoint == nil { known.endpoint = endpoint }
            if known.region == nil { known.region = region }
            if known.modelID == nil { known.modelID = modelID }
            return known
        }
        if error is CancellationError {
            return SiliconFlowError(kind: .cancelled, endpoint: endpoint, region: region, modelID: modelID)
        }
        if let urlError = error as? URLError {
            return SiliconFlowError(
                kind: FailureClassifier.classify(urlErrorCode: urlError.code),
                endpoint: endpoint,
                underlying: "URLError \(urlError.code.rawValue): \(urlError.localizedDescription)",
                region: region,
                modelID: modelID
            )
        }
        if let decoding = error as? DecodingError {
            return SiliconFlowError(
                kind: .decodingFailed,
                endpoint: endpoint,
                underlying: DecodingErrorDescriber.describe(decoding),
                region: region,
                modelID: modelID
            )
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            // Apple では非 Optional、Linux では Optional を返すため型を明示して両対応
            let code: URLError.Code? = URLError.Code(rawValue: nsError.code)
            return SiliconFlowError(
                kind: code.map(FailureClassifier.classify(urlErrorCode:)) ?? .connectionFailed,
                endpoint: endpoint,
                underlying: "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)",
                region: region,
                modelID: modelID
            )
        }
        return SiliconFlowError(
            kind: .unknown,
            endpoint: endpoint,
            underlying: String(describing: error),
            region: region,
            modelID: modelID
        )
    }

    /// サポートへの問い合わせや Issue 報告に貼り付けられる技術情報
    public var technicalReport: String {
        var lines: [String] = ["種類: \(kind.rawValue)"]
        if let endpoint { lines.append("エンドポイント: \(endpoint)") }
        if let region { lines.append("リージョン: \(region.displayName)") }
        if let modelID { lines.append("モデル: \(modelID)") }
        if let httpStatus { lines.append("HTTP ステータス: \(httpStatus)") }
        if let apiCode { lines.append("SiliconFlow エラーコード: \(apiCode)") }
        if let serverMessage { lines.append("サーバーのメッセージ: \(serverMessage)") }
        if let traceID { lines.append("トレース ID: \(traceID)") }
        if let retryAfter { lines.append("Retry-After: \(NumberText.compact(retryAfter)) 秒") }
        if let underlying { lines.append("詳細: \(underlying)") }
        if let bodySnippet, bodySnippet != serverMessage { lines.append("応答本文: \(bodySnippet)") }
        return lines.joined(separator: "\n")
    }
}

/// DecodingError を人が読める形にします。
enum DecodingErrorDescriber {
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "型が一致しません (\(type)) at \(path(context))"
        case .valueNotFound(let type, let context):
            return "値がありません (\(type)) at \(path(context))"
        case .keyNotFound(let key, let context):
            return "キー '\(key.stringValue)' がありません at \(path(context))"
        case .dataCorrupted(let context):
            return "データが壊れています at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        return components.isEmpty ? "(root)" : components.joined(separator: ".")
    }
}
