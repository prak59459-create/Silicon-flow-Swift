import SwiftUI
import SiliconFlowKit

/// API キーの入力欄（表示切り替え・貼り付けボタン・形式チェック付き）
struct KeyInputField: View {
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                field
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isRevealed ? "キーを隠す" : "キーを表示")
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { text = first }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            KeyValidationMessages(text: text)
        }
    }

    @ViewBuilder
    private var field: some View {
        if isRevealed {
            TextField("sk-...", text: $text)
        } else {
            SecureField("sk-...", text: $text)
        }
    }
}

/// 入力中のキーの形式チェック結果
struct KeyValidationMessages: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            let result = APIKeyValidator.validate(text)
            if result.issues.isEmpty {
                Label("形式は正常です", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.issues, id: \.self) { issue in
                        Label(issue.message, systemImage: issue.isBlocking ? "xmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
                    }
                }
            }
        }
    }
}

/// キーの確認状態
enum KeyVerificationState {
    case idle
    case checking
    case success(RegionDetector.Result)
    case failure(SiliconFlowError)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

/// キーを確認して保存する処理（初期設定と設定画面で共通）
@MainActor
enum KeyVerifier {
    /// 両リージョンで認証を試し、通った方に保存します。
    static func verifyAndSave(_ rawKey: String, preferred: APIRegion, settings: AppSettings) async -> KeyVerificationState {
        let key = APIKeyValidator.sanitize(rawKey)
        let validation = APIKeyValidator.validate(key)
        guard validation.isUsable else {
            let kind: FailureKind = validation.issues.contains(.empty) ? .missingAPIKey : .malformedAPIKey
            return .failure(SiliconFlowError(kind: kind, underlying: validation.issues.map(\.message).joined(separator: " "), region: preferred))
        }
        let (result, errors) = await RegionDetector.detect(apiKey: key, preferred: preferred)
        guard let result else {
            return .failure(errors[preferred] ?? errors.values.first ?? SiliconFlowError(kind: .unknown, region: preferred))
        }
        settings.saveAPIKey(key, for: result.region)
        if settings.region != result.region { settings.region = result.region }
        return .success(result)
    }

    /// 通信できない環境でも、確認せずにキーを保存できるようにします。
    static func saveWithoutVerification(_ rawKey: String, region: APIRegion, settings: AppSettings) -> Bool {
        let key = APIKeyValidator.sanitize(rawKey)
        guard APIKeyValidator.validate(key).isUsable else { return false }
        let saved = settings.saveAPIKey(key, for: region)
        if settings.region != region { settings.region = region }
        return saved
    }

    /// 通信の問題（キーの問題ではない）か
    static func isNetworkProblem(_ error: SiliconFlowError) -> Bool {
        let kinds: Set<FailureKind> = [.offline, .timedOut, .dnsFailure, .connectionFailed, .tlsFailure, .unexpectedResponse, .serverError, .badGateway, .overloaded, .gatewayTimeout]
        return kinds.contains(error.kind)
    }
}
