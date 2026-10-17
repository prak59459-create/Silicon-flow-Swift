import SwiftUI
import SiliconFlowKit

/// 設定画面
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                APIKeySection()
                ConnectionSection()
                CatalogSettingsSection()
                Section("チャット") {
                    NavigationLink {
                        ChatParametersForm()
                            .navigationTitle("チャットの設定")
                    } label: {
                        Label("生成パラメータの既定値", systemImage: "slider.horizontal.3")
                    }
                }
                AboutSection()
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

/// API キーの登録・確認・削除
private struct APIKeySection: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var draftKey = ""
    @State private var state: KeyVerificationState = .idle

    var body: some View {
        Section {
            Picker("リージョン", selection: $settings.region) {
                ForEach(APIRegion.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            storedKeyRow
            KeyInputField(text: $draftKey)
            Button {
                verify()
            } label: {
                HStack {
                    Label("保存して接続を確認", systemImage: "checkmark.shield")
                    if state.isChecking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(draftKey.isEmpty || state.isChecking)
            stateView
            if settings.hasKeyForCurrentRegion {
                Button(role: .destructive) {
                    settings.deleteAPIKey(for: settings.region)
                } label: {
                    Label("\(settings.region.shortName)のキーを削除", systemImage: "trash")
                }
            }
            Link(destination: settings.region.apiKeysURL) {
                Label("API キーを発行する（\(settings.region.shortName)）", systemImage: "safari")
            }
        } header: {
            Text("API キー")
        } footer: {
            Text("キーは端末のキーチェーンに保存され、SiliconFlow 以外には送信されません。中国版と国際版のキーは別々に保存できます。")
        }
    }

    @ViewBuilder
    private var storedKeyRow: some View {
        if let key = settings.currentAPIKey {
            LabeledContent("保存中のキー", value: TextSanitizer.masked(key))
                .font(.body.monospaced())
        } else {
            Label("\(settings.region.shortName)のキーはまだ登録されていません", systemImage: "key")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch state {
        case .idle, .checking:
            EmptyView()
        case .success(let result):
            Label("\(result.region.displayName)で認証できました。保存しました。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let restriction = result.restriction {
                ErrorCardView(error: restriction, compact: true)
            }
        case .failure(let error):
            ErrorCardView(error: error, compact: true, retry: { verify() })
            if KeyVerifier.allowsSavingWithoutVerification(error) {
                Button("確認せずに保存する") {
                    if KeyVerifier.saveWithoutVerification(draftKey, region: settings.region, settings: settings) {
                        draftKey = ""
                        state = .idle
                    }
                }
            }
        }
    }

    private func verify() {
        let key = draftKey
        let preferred = settings.region
        state = .checking
        Task {
            let result = await KeyVerifier.verifyAndSave(key, preferred: preferred, settings: settings)
            state = result
            if case .success = result { draftKey = "" }
        }
    }
}

/// 接続先とタイムアウト
private struct ConnectionSection: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Section {
            Toggle("カスタム URL を使う", isOn: $settings.customBaseURLEnabled)
            if settings.customBaseURLEnabled {
                TextField("https://example.com/v1", text: $settings.customBaseURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                urlStatus
                Button("この URL で接続し直す") { settings.applyCustomBaseURL() }
            }
            Stepper(value: $settings.requestTimeout, in: 30...600, step: 30) {
                LabeledContent("タイムアウト", value: "\(Int(settings.requestTimeout)) 秒")
            }
        } header: {
            Text("接続")
        } footer: {
            Text("通常はカスタム URL は不要です。現在の接続先: \(settings.makeClient().configuration.baseURL.absoluteString)")
        }
    }

    @ViewBuilder
    private var urlStatus: some View {
        switch BaseURLNormalizer.normalize(settings.customBaseURLText) {
        case .success(let url):
            Label("使用する URL: \(url.absoluteString)", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let failure):
            Label(message(for: failure), systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func message(for failure: BaseURLNormalizer.Failure) -> String {
        switch failure {
        case .empty: return "URL を入力してください（空のままなら標準の接続先を使います）"
        case .invalid: return "URL の形式が正しくありません"
        case .insecure: return "安全のため https:// の URL を指定してください"
        }
    }
}
