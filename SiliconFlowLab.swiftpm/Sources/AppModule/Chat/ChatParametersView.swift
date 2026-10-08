import SwiftUI
import SiliconFlowKit

/// チャットの生成パラメータのシート
struct ChatParametersView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatParametersForm()
                .navigationTitle("チャットの設定")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { dismiss() }
                    }
                }
        }
    }
}

/// チャットの生成パラメータ（すべてのモデル共通の既定値）
struct ChatParametersForm: View {
    @EnvironmentObject private var settings: AppSettings

    private static let maxTokenChoices = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
    private static let budgetChoices = [512, 1024, 2048, 4096, 8192, 16384, 32768]

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.chatParameters.systemPrompt)
                    .frame(minHeight: 90)
            } header: {
                Text("システムプロンプト")
            } footer: {
                Text("モデルへの役割や口調の指示です（例: あなたは親切な日本語アシスタントです）。空なら送りません。")
            }
            generationSection
            thinkingSection
            Section {
                Stepper(value: $settings.chatParameters.historyLimit, in: 1...100) {
                    LabeledContent("送る履歴", value: "直近 \(settings.chatParameters.historyLimit) 件")
                }
            } header: {
                Text("会話の履歴")
            } footer: {
                Text("長い会話はトークン数（＝料金）が増えます。上限を超えると古いものから送らなくなります。")
            }
            Section {
                Button("既定値に戻す", role: .destructive) {
                    settings.resetChatParameters()
                }
            }
        }
    }

    private var generationSection: some View {
        Section {
            SliderRow(title: "温度（temperature）", value: $settings.chatParameters.temperature, range: 0...2, step: 0.05, help: "高いほど多様で創造的、低いほど安定した回答になります。")
            SliderRow(title: "top_p", value: $settings.chatParameters.topP, range: 0.01...1, step: 0.01, help: "候補にする単語の範囲。通常は 0.7〜1.0 のままで構いません。")
            Picker("最大トークン数", selection: $settings.chatParameters.maxTokens) {
                ForEach(tokenOptions, id: \.self) { value in
                    Text(DisplayFormat.tokens(value)).tag(value)
                }
            }
            Toggle("ストリーミング（少しずつ表示）", isOn: $settings.chatParameters.useStreaming)
            Toggle("JSON モード", isOn: $settings.chatParameters.jsonMode)
        } header: {
            Text("生成")
        } footer: {
            Text("ストリーミングをオンにすると、長い回答でもタイムアウトしにくくなります。JSON モードは対応モデルでのみ使えます。")
        }
    }

    private var thinkingSection: some View {
        Section {
            Picker("思考モード", selection: $settings.chatParameters.thinking) {
                ForEach(ChatParameters.ThinkingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if settings.chatParameters.thinking == .on {
                Picker("思考の予算（トークン）", selection: $settings.chatParameters.thinkingBudget) {
                    ForEach(budgetOptions, id: \.self) { value in
                        Text(DisplayFormat.tokens(value)).tag(value)
                    }
                }
            }
        } header: {
            Text("思考（推論）モデル")
        } footer: {
            Text("Qwen3・DeepSeek-V3.1 以降などは思考のオン/オフを切り替えられます。対応していないモデルで指定するとエラーになるので、その場合は「自動」に戻してください。")
        }
    }

    /// 現在の値が選択肢に無くても選べるようにします。
    private var tokenOptions: [Int] {
        Self.withCurrent(Self.maxTokenChoices, settings.chatParameters.maxTokens)
    }

    private var budgetOptions: [Int] {
        Self.withCurrent(Self.budgetChoices, settings.chatParameters.thinkingBudget)
    }

    private static func withCurrent(_ options: [Int], _ current: Int) -> [Int] {
        options.contains(current) ? options : (options + [current]).sorted()
    }
}

/// ラベル・値・説明付きのスライダー
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(NumberText.fixed(value, fractionDigits: 2))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
