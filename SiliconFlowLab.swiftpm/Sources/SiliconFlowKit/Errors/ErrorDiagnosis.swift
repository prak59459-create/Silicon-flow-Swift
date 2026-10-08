import Foundation

/// 失敗に対して画面に出せる操作
public enum DiagnosisAction: Hashable, Sendable {
    case retry
    case openURL(title: String, url: URL)
    case switchRegion(APIRegion)
    case editAPIKey
    case refreshModels
    case chooseAnotherModel
    case reduceMaxTokens
    case disableThinking
    case enableStreaming
    case runDiagnostics

    public var title: String {
        switch self {
        case .retry: return "再試行"
        case .openURL(let title, _): return title
        case .switchRegion(let region): return "\(region.shortName)に切り替える"
        case .editAPIKey: return "API キーを入力し直す"
        case .refreshModels: return "モデル一覧を更新"
        case .chooseAnotherModel: return "別のモデルを選ぶ"
        case .reduceMaxTokens: return "最大トークン数を減らす"
        case .disableThinking: return "思考モードをオフにする"
        case .enableStreaming: return "ストリーミングをオンにする"
        case .runDiagnostics: return "接続診断を実行"
        }
    }

    public var systemImage: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .openURL: return "safari"
        case .switchRegion: return "globe.asia.australia"
        case .editAPIKey: return "key"
        case .refreshModels: return "arrow.triangle.2.circlepath"
        case .chooseAnotherModel: return "square.stack.3d.up"
        case .reduceMaxTokens: return "text.badge.minus"
        case .disableThinking: return "brain"
        case .enableStreaming: return "dot.radiowaves.left.and.right"
        case .runDiagnostics: return "stethoscope"
        }
    }
}

/// 「なぜ失敗したか」「どうすれば直るか」
public struct ErrorDiagnosis: Sendable, Equatable {
    public enum Severity: String, Sendable {
        case info
        case warning
        case error
    }

    public var kind: FailureKind
    /// 何が起きたか（一行）
    public var title: String
    /// なぜ失敗したか
    public var cause: String
    /// どうすれば直るか（上から順に試す）
    public var fixes: [String]
    public var actions: [DiagnosisAction]
    public var isRetryable: Bool
    public var severity: Severity

    public init(
        kind: FailureKind,
        title: String,
        cause: String,
        fixes: [String],
        actions: [DiagnosisAction] = [],
        isRetryable: Bool = false,
        severity: Severity = .error
    ) {
        self.kind = kind
        self.title = title
        self.cause = cause
        self.fixes = fixes
        self.actions = actions
        self.isRetryable = isRetryable
        self.severity = severity
    }
}
