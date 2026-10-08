import SwiftUI
import SiliconFlowKit

/// 音声合成モデルを試す：文章を読み上げる
struct SpeechPlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @StateObject private var runner = RequestRunner<SpeechResult>()
    @StateObject private var player = AudioPlayer()
    @State private var text = "こんにちは。SiliconFlow の音声合成を試しています。"
    @State private var voice = "alex"
    @State private var speed = 1.0
    @State private var format = "mp3"

    struct SpeechResult {
        let id = UUID()
        let data: Data
        let fileURL: URL?
    }

    private static let defaultVoice = "（モデルの既定）"

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "読み上げる文章", systemImage: "text.bubble") {
                InputEditor(placeholder: "読み上げる文章", text: $text, minHeight: 90)
                Text("\(text.utf8.count) バイト（料金はバイト数で決まるモデルがあります）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PlaygroundCard(title: "声と設定", systemImage: "person.wave.2") {
                Picker("声", selection: $voice) {
                    Text(Self.defaultVoice).tag(Self.defaultVoice)
                    ForEach(SpeechRequest.presetVoices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                SliderRow(title: "速さ", value: $speed, range: 0.25...4, step: 0.05, help: "1.0 が標準です。")
                Picker("形式", selection: $format) {
                    ForEach(["mp3", "wav", "opus"], id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            RunButton(title: "音声を作る", systemImage: "waveform", isRunning: runner.isRunning, isDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note: PriceNote.text(for: model), action: { run() }, cancel: { runner.cancel() })
            if let error = runner.error {
                ErrorCardView(error: error, retry: { run() }, dismiss: { runner.dismissError() })
            }
            if let result = runner.output {
                speechResult(result)
            }
        }
        .onChange(of: runner.output?.id) {
            // 結果が届いたら自動で再生します
            guard let data = runner.output?.data else { return }
            player.load(data)
            player.play()
        }
        .onDisappear { player.stop() }
    }

    private func speechResult(_ result: SpeechResult) -> some View {
        PlaygroundCard(title: "結果", systemImage: "speaker.wave.2") {
            HStack(spacing: 12) {
                Button {
                    if player.isPlaying { player.stop() } else { player.play() }
                } label: {
                    Label(player.isPlaying ? "停止" : "再生", systemImage: player.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                if let fileURL = result.fileURL {
                    ShareLink(item: fileURL) {
                        Label("共有・保存", systemImage: "square.and.arrow.up")
                    }
                }
            }
            FlowLayout(spacing: 16, lineSpacing: 10) {
                ResultMetric(title: "長さ", value: DisplayFormat.duration(player.duration))
                ResultMetric(title: "サイズ", value: DisplayFormat.bytes(result.data.count))
                if let cost = CostEstimator.cost(inputTokens: text.utf8.count, entry: model.catalog), model.catalog?.unit == .perMillionBytes {
                    ResultMetric(title: "料金の目安", value: DisplayFormat.money(cost, rates: settings.showYen ? store.exchangeRates : nil, showYen: settings.showYen))
                }
            }
            if let message = player.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func run() {
        let client = settings.makeClient()
        let voiceID: String? = voice == Self.defaultVoice ? nil : SpeechRequest.voiceID(model: model.id, voice: voice)
        let request = SpeechRequest(model: model.id, input: text, voice: voiceID, responseFormat: format, speed: speed)
        let fileName = "speech.\(format)"
        player.stop()
        runner.run(region: client.region, modelID: model.id) {
            let data = try await client.speech(request)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            let saved = (try? data.write(to: url, options: .atomic)) != nil
            return SpeechResult(data: data, fileURL: saved ? url : nil)
        }
    }
}
