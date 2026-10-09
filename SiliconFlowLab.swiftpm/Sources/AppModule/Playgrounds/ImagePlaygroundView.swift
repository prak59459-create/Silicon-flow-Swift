import PhotosUI
import SwiftUI
import SiliconFlowKit

/// 画像生成・画像編集モデルを試す
struct ImagePlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @StateObject private var runner = RequestRunner<ImageGenerationResponse>()
    @State private var prompt = "夕暮れの海辺に建つ小さな灯台、柔らかい光、水彩画風"
    @State private var negativePrompt = ""
    @State private var imageSize = "1024x1024"
    @State private var useAdvanced = false
    @State private var steps = 20
    @State private var guidance = 7.5
    @State private var seedText = ""
    @State private var sourceItem: PhotosPickerItem?
    @State private var sourceImage: String?

    private var needsSourceImage: Bool { model.category == .imageToImage }

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "プロンプト", systemImage: "text.cursor") {
                InputEditor(placeholder: "作りたい画像の説明", text: $prompt, minHeight: 80)
                TextField("ネガティブプロンプト（入れたくないもの・任意）", text: $negativePrompt)
                    .textFieldStyle(.roundedBorder)
            }
            if needsSourceImage {
                sourceImageCard
            }
            optionsCard
            RunButton(title: "画像を生成", systemImage: "wand.and.stars", isRunning: runner.isRunning, isDisabled: isInputInvalid, note: PriceNote.text(for: model), action: { run() }, cancel: { runner.cancel() })
            if let error = runner.error {
                ErrorCardView(error: error, retry: { run() }, dismiss: { runner.dismissError() })
            }
            if let response = runner.output {
                ImageResultView(response: response, elapsed: runner.elapsed, cost: CostEstimator.cost(units: response.images.count, entry: model.catalog), rates: settings.showYen ? store.exchangeRates : nil)
            }
        }
        .onChange(of: sourceItem) {
            Task { await loadSource() }
        }
    }

    private var sourceImageCard: some View {
        PlaygroundCard(title: "元の画像", systemImage: "photo") {
            HStack(spacing: 12) {
                if let sourceImage, let image = ImageEncoder.image(fromDataURL: sourceImage) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                PhotosPicker(selection: $sourceItem, matching: .images) {
                    Label(sourceImage == nil ? "写真を選ぶ" : "写真を変更", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var optionsCard: some View {
        PlaygroundCard(title: "設定", systemImage: "slider.horizontal.3") {
            Picker("サイズ", selection: $imageSize) {
                ForEach(ImageGenerationRequest.commonSizes, id: \.self) { size in
                    Text(size).tag(size)
                }
            }
            Toggle("詳細設定を送る（ステップ数・ガイダンス・シード）", isOn: $useAdvanced)
            if useAdvanced {
                Stepper("ステップ数: \(steps)", value: $steps, in: 1...50)
                SliderRow(title: "ガイダンス", value: $guidance, range: 0...20, step: 0.5, help: "大きいほどプロンプトに忠実になります。対応していないモデルもあります。")
                TextField("シード（空欄ならランダム）", text: $seedText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            Text("サイズや詳細設定に対応していないモデルではエラーになることがあります。その場合は既定値に戻してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isInputInvalid: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (needsSourceImage && sourceImage == nil)
    }

    private func loadSource() async {
        guard let sourceItem, let data = try? await sourceItem.loadTransferable(type: Data.self) else { return }
        sourceImage = ImageEncoder.dataURL(from: data)
    }

    private func run() {
        let client = settings.makeClient()
        var request = ImageGenerationRequest(model: model.id, prompt: prompt, negativePrompt: negativePrompt, imageSize: imageSize, batchSize: 1, image: sourceImage)
        if useAdvanced {
            request.numInferenceSteps = steps
            request.guidanceScale = guidance
            request.seed = Int(seedText.trimmingCharacters(in: .whitespaces))
        }
        let finalRequest = request
        runner.run(region: client.region, modelID: model.id) {
            try await client.generateImage(finalRequest)
        }
    }
}

private struct ImageResultView: View {
    let response: ImageGenerationResponse
    let elapsed: TimeInterval?
    let cost: Money?
    let rates: ExchangeRates?

    var body: some View {
        PlaygroundCard(title: "結果", systemImage: "photo.on.rectangle") {
            ForEach(response.imageURLs, id: \.self) { url in
                GeneratedImageView(url: url)
            }
            FlowLayout(spacing: 16, lineSpacing: 10) {
                if let elapsed {
                    ResultMetric(title: "所要時間", value: DisplayFormat.duration(elapsed))
                }
                if let inference = response.timings?.inference {
                    ResultMetric(title: "推論時間", value: DisplayFormat.duration(inference))
                }
                if let seed = response.seed {
                    ResultMetric(title: "シード", value: "\(seed)")
                }
                if let cost {
                    ResultMetric(title: "料金", value: DisplayFormat.money(cost, rates: rates, showYen: rates != nil))
                }
            }
            Text("画像の URL は 1 時間で無効になります。残したい画像は共有ボタンから保存してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GeneratedImageView: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .failure:
                    Label("画像を読み込めませんでした", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
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
