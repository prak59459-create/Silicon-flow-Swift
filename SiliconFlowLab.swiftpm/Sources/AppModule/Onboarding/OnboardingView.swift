import SwiftUI
import SiliconFlowKit

/// 初回起動時：API キーの入力と接続確認
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var draftKey = ""
    @State private var preferredRegion: APIRegion = .china
    @State private var state: KeyVerificationState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeader()
                OnboardingSteps()
                keyCard
                if case .failure(let error) = state {
                    ErrorCardView(error: error, retry: { connect() })
                    if KeyVerifier.isNetworkProblem(error) {
                        Button("確認せずに保存して始める") {
                            _ = KeyVerifier.saveWithoutVerification(draftKey, region: preferredRegion, settings: settings)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                OnboardingLinks()
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { preferredRegion = settings.region }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API キー")
                .font(.headline)
            Picker("キーを作ったサイト", selection: $preferredRegion) {
                ForEach(APIRegion.allCases) { region in
                    Text(region.shortName).tag(region)
                }
            }
            .pickerStyle(.segmented)
            Text("どちらで作ったか分からなくても大丈夫です。両方で自動的に確認します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            KeyInputField(text: $draftKey)
            Button {
                connect()
            } label: {
                HStack {
                    if state.isChecking {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(state.isChecking ? "確認中…" : "接続してモデル一覧を見る")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftKey.isEmpty || state.isChecking)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private func connect() {
        let key = draftKey
        let preferred = preferredRegion
        state = .checking
        Task {
            state = await KeyVerifier.verifyAndSave(key, preferred: preferred, settings: settings)
        }
    }
}

private struct OnboardingHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("SiliconFlow Lab")
                .font(.largeTitle.bold())
            Text("SiliconFlow の API キーを入れると、あなたが使えるモデルの一覧・料金・パラメータ数を確認して、その場で試せます。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepRow(number: 1, text: "SiliconFlow（中国版 siliconflow.cn または 国際版 siliconflow.com）でアカウントを作ります。")
            StepRow(number: 2, text: "コンソールの「API キー」ページで新しいキーを作り、コピーします。")
            StepRow(number: 3, text: "下の欄に貼り付けて「接続」を押します。キーは端末のキーチェーンに保存されます。")
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(APIRegion.allCases) { region in
                Link(destination: region.apiKeysURL) {
                    Label("\(region.displayName) で API キーを作る", systemImage: "safari")
                }
            }
        }
        .font(.subheadline)
    }
}
