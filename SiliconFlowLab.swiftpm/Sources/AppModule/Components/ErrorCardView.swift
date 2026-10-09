import SwiftUI
import SiliconFlowKit

/// 失敗したときに「なぜ失敗したか」「どうすれば直るか」を表示するカード
struct ErrorCardView: View {
    let error: SiliconFlowError
    var compact: Bool = false
    var retry: (() -> Void)?
    var dismiss: (() -> Void)?

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: ModelStore
    @Environment(\.openURL) private var openURL

    private var diagnosis: ErrorDiagnosis { error.diagnosis }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(diagnosis.cause)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !compact {
                FixListView(fixes: diagnosis.fixes)
            }
            actionButtons
            ErrorDetailsView(error: error)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(0.35)))
    }

    private var accent: Color {
        switch diagnosis.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var icon: String {
        switch diagnosis.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .font(.title3)
            Text(diagnosis.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("閉じる")
            }
        }
    }

    private var visibleActions: [DiagnosisAction] {
        let isChat = (error.endpoint ?? "").contains("chat/completions")
        return diagnosis.actions.filter { action in
            switch action {
            case .retry: return retry != nil
            case .reduceMaxTokens, .disableThinking, .enableStreaming: return isChat && retry != nil
            case .chooseAnotherModel: return router.selectedModelID != nil
            default: return true
            }
        }
    }

    private var actionButtons: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(visibleActions, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(action == .retry ? accent : Color.accentColor)
            }
        }
    }

    private func perform(_ action: DiagnosisAction) {
        switch action {
        case .retry:
            retry?()
        case .openURL(_, let url):
            openURL(url)
        case .switchRegion(let region):
            settings.region = region
            if !settings.hasKeyForCurrentRegion { router.show(.settings) }
        case .editAPIKey:
            router.show(.settings)
        case .refreshModels:
            store.reload(settings: settings)
        case .chooseAnotherModel:
            router.selectedModelID = nil
        case .reduceMaxTokens:
            settings.chatParameters.maxTokens = max(256, settings.chatParameters.maxTokens / 2)
            retry?()
        case .disableThinking:
            settings.chatParameters.thinking = .off
            retry?()
        case .enableStreaming:
            settings.chatParameters.useStreaming = true
            retry?()
        case .runDiagnostics:
            router.show(.diagnostics)
        }
    }
}

/// 直し方の番号付きリスト
private struct FixListView: View {
    let fixes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("直し方")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(fixes.enumerated()), id: \.offset) { index, fix in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(fix)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 技術情報（折りたたみ・コピー可）
private struct ErrorDetailsView: View {
    let error: SiliconFlowError
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(error.technicalReport)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                CopyButton(text: error.technicalReport, title: "技術情報をコピー")
                    .font(.caption)
            }
            .padding(.top, 4)
        } label: {
            Text("技術情報")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
