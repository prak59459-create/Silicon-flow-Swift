import AVKit
import PhotosUI
import SwiftUI
import SiliconFlowKit

/// 動画生成モデルを試す（受付 → 数分おきに状態を確認 → 完成したら再生）
struct VideoPlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var job = VideoJob()
    @State private var prompt = "桜並木の道を歩く柴犬、春の柔らかい日差し、シネマティック"
    @State private var negativePrompt = ""
    @State private var imageSize = "1280x720"
    @State private var sourceItem: PhotosPickerItem?
    @State private var sourceImage: String?

    private var needsSourceImage: Bool { model.category == .imageToVideo }

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "プロンプト", systemImage: "text.cursor") {
                InputEditor(placeholder: "作りたい動画の説明", text: $prompt, minHeight: 80)
                TextField("ネガティブプロンプト（任意）", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
                Picker("サイズ", selection: $imageSize) {
                    ForEach(VideoSubmitRequest.commonSizes, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
            }
            if needsSourceImage {
                PlaygroundCard(title: "元の画像", systemImage: "photo") {
                    PhotosPicker(selection: $sourceItem, matching: .images) {
                        Label(sourceImage == nil ? "写真を選ぶ" : "写真を変更（選択済み）", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Label("動画生成は 1 本ごとに料金がかかり、完成まで数分かかります。", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            RunButton(title: "動画を生成", systemImage: "film", isRunning: job.isRunning, isDisabled: isInputInvalid, note: PriceNote.text(for: model), action: { start() }, cancel: { job.cancel() })
            if let error = job.error {
                ErrorCardView(error: error, retry: { start() }, dismiss: { job.dismissError() })
            }
            VideoJobStatusView(job: job)
        }
        .onChange(of: sourceItem) {
            Task { await loadSource() }
        }
        .onDisappear { job.player?.pause() }
    }

    private var isInputInvalid: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (needsSourceImage && sourceImage == nil)
    }

    private func loadSource() async {
        guard let sourceItem, let data = try? await sourceItem.loadTransferable(type: Data.self) else { return }
        sourceImage = ImageEncoder.dataURL(from: data)
    }

    private func start() {
        let request = VideoSubmitRequest(model: model.id, prompt: prompt, negativePrompt: negativePrompt, imageSize: imageSize, image: sourceImage)
        job.start(client: settings.makeClient(), request: request)
    }
}

private struct VideoJobStatusView: View {
    @ObservedObject var job: VideoJob

    var body: some View {
        if let requestID = job.requestID {
            PlaygroundCard(title: "状態: \(job.status.label)", systemImage: "hourglass") {
                Text("受付番号: \(requestID)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                if job.isRunning {
                    Text("経過 \(DisplayFormat.duration(job.elapsed))。10 秒ごとに確認しています。画面を離れても受付は続きますが、確認は止まります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = job.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let player = job.player {
                    VideoPlayer(player: player)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if let url = job.videoURL {
                    HStack {
                        ShareLink(item: url) {
                            Label("共有・保存", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Link(destination: url) {
                            Label("ブラウザで開く", systemImage: "safari")
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// 動画生成ジョブ（受付と状態確認のくり返し）
@MainActor
final class VideoJob: ObservableObject {
    @Published private(set) var requestID: String?
    @Published private(set) var status: VideoStatusResponse.Status = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var error: SiliconFlowError?
    @Published private(set) var failureReason: String?
    @Published private(set) var videoURL: URL?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var elapsed: TimeInterval = 0

    private var task: Task<Void, Never>?
    private let pollInterval: UInt64 = 10_000_000_000
    private let timeout: TimeInterval = 20 * 60

    func start(client: SiliconFlowClient, request: VideoSubmitRequest) {
        task?.cancel()
        requestID = nil
        status = .unknown
        error = nil
        failureReason = nil
        videoURL = nil
        player = nil
        elapsed = 0
        isRunning = true
        task = Task { [weak self] in
            await self?.run(client: client, request: request)
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    func dismissError() {
        error = nil
    }

    private func run(client: SiliconFlowClient, request: VideoSubmitRequest) async {
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let submitted = try await client.submitVideo(request)
            requestID = submitted.requestID
            status = .inQueue
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: pollInterval)
                elapsed = ProcessInfo.processInfo.systemUptime - start
                let response = try await client.videoStatus(requestID: submitted.requestID)
                status = response.status
                if response.status == .succeed, let url = response.videoURLs.first {
                    videoURL = url
                    player = AVPlayer(url: url)
                    break
                }
                if response.status == .failed {
                    failureReason = response.reason.map { "失敗の理由: \($0)" } ?? "生成に失敗しました。"
                    break
                }
                if elapsed > timeout {
                    failureReason = "20 分たっても完成しませんでした。受付番号を控えて、後で公式コンソールから確認してください。"
                    break
                }
            }
        } catch {
            let wrapped = SiliconFlowError.wrap(error, region: client.region, modelID: request.model)
            if !wrapped.isCancellation { self.error = wrapped }
        }
        isRunning = false
    }
}
