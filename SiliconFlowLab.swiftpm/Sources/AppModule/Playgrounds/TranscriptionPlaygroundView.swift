import SwiftUI
import UniformTypeIdentifiers
import SiliconFlowKit

/// 音声認識モデルを試す：音声ファイルを文字に起こす
struct TranscriptionPlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var runner = RequestRunner<TranscriptionResponse>()
    @State private var showsImporter = false
    @State private var audio: AudioFile?
    @State private var importError: String?

    struct AudioFile {
        let name: String
        let data: Data
        let mimeType: String
    }

    /// 送れるファイルの上限（大きすぎるとメモリと通信量を圧迫するため）
    private static let maxBytes = 30 * 1024 * 1024

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "音声ファイル", systemImage: "waveform") {
                if let audio {
                    Label("\(audio.name)（\(DisplayFormat.bytes(audio.data.count))）", systemImage: "music.note")
                        .font(.subheadline)
                } else {
                    Text("ファイル App から音声ファイル（mp3・wav・m4a など）を選んでください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showsImporter = true
                } label: {
                    Label(audio == nil ? "ファイルを選ぶ" : "別のファイルを選ぶ", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            RunButton(title: "文字に起こす", systemImage: "text.bubble", isRunning: runner.isRunning, isDisabled: audio == nil, note: PriceNote.text(for: model), action: { run() }, cancel: { runner.cancel() })
            if let error = runner.error {
                ErrorCardView(error: error, retry: { run() }, dismiss: { runner.dismissError() })
            }
            if let result = runner.output {
                PlaygroundCard(title: "結果", systemImage: "checkmark.circle") {
                    Text(result.text.isEmpty ? "（音声から文字が見つかりませんでした）" : result.text)
                        .textSelection(.enabled)
                    CopyButton(text: result.text)
                        .buttonStyle(.bordered)
                }
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= Self.maxBytes else {
                    importError = "ファイルが大きすぎます（\(DisplayFormat.bytes(size))）。30 MB 以下にしてください。"
                    return
                }
                let data = try Data(contentsOf: url)
                audio = AudioFile(name: url.lastPathComponent, data: data, mimeType: MultipartFormData.audioMimeType(forExtension: url.pathExtension))
            } catch {
                importError = "ファイルを読み込めませんでした: \(error.localizedDescription)"
            }
        case .failure(let error):
            importError = "ファイルを開けませんでした: \(error.localizedDescription)"
        }
    }

    private func run() {
        guard let audio else { return }
        let client = settings.makeClient()
        let modelID = model.id
        runner.run(region: client.region, modelID: modelID) {
            try await client.transcribe(audio: audio.data, fileName: audio.name, mimeType: audio.mimeType, model: modelID)
        }
    }
}
