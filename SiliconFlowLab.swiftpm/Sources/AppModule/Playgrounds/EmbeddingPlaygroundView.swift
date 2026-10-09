import SwiftUI
import SiliconFlowKit

/// 埋め込みモデルを試す：文章をベクトルにして、2 つの文の近さ（コサイン類似度）を表示
struct EmbeddingPlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @StateObject private var runner = RequestRunner<EmbeddingResult>()
    @State private var textA = "SiliconFlow は高速で安価な推論 API を提供しています。"
    @State private var textB = "SiliconFlow offers a fast and affordable inference API."

    struct EmbeddingResult {
        let dimensions: Int
        let preview: [Double]
        let norms: [Double]
        let similarity: Double?
        let tokens: Int?
        let cost: Money?
    }

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "文章", systemImage: "text.quote") {
                InputEditor(placeholder: "文章 A", text: $textA, minHeight: 70)
                InputEditor(placeholder: "文章 B（任意・類似度を計算します）", text: $textB, minHeight: 70)
            }
            RunButton(title: "ベクトルに変換", systemImage: "circle.hexagongrid", isRunning: runner.isRunning, isDisabled: inputs.isEmpty, note: PriceNote.text(for: model), action: { run() }, cancel: { runner.cancel() })
            if let error = runner.error {
                ErrorCardView(error: error, retry: { run() }, dismiss: { runner.dismissError() })
            }
            if let result = runner.output {
                EmbeddingResultView(result: result, rates: settings.showYen ? store.exchangeRates : nil)
            }
        }
    }

    private var inputs: [String] {
        [textA, textB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func run() {
        let client = settings.makeClient()
        let request = EmbeddingRequest(model: model.id, input: inputs)
        let entry = model.catalog
        runner.run(region: client.region, modelID: model.id) {
            let response = try await client.embeddings(request)
            let vectors = response.vectors
            guard let first = vectors.first else {
                throw SiliconFlowError(kind: .emptyResponse, endpoint: "POST /embeddings", region: client.region, modelID: request.model)
            }
            let similarity: Double? = vectors.count >= 2 ? VectorMath.cosineSimilarity(vectors[0], vectors[1]) : nil
            let tokens = response.usage?.promptTokens ?? response.usage?.totalTokens
            return EmbeddingResult(
                dimensions: first.count,
                preview: Array(first.prefix(8)),
                norms: vectors.map(VectorMath.norm),
                similarity: similarity,
                tokens: tokens,
                cost: tokens.flatMap { CostEstimator.cost(inputTokens: $0, entry: entry) }
            )
        }
    }
}

private struct EmbeddingResultView: View {
    let result: EmbeddingPlaygroundView.EmbeddingResult
    let rates: ExchangeRates?

    var body: some View {
        PlaygroundCard(title: "結果", systemImage: "checkmark.circle") {
            FlowLayout(spacing: 16, lineSpacing: 10) {
                ResultMetric(title: "次元数", value: "\(result.dimensions)")
                if let tokens = result.tokens {
                    ResultMetric(title: "トークン", value: DisplayFormat.tokens(tokens))
                }
                if let cost = result.cost {
                    ResultMetric(title: "料金", value: DisplayFormat.money(cost, rates: rates, showYen: rates != nil))
                }
            }
            if let similarity = result.similarity {
                VStack(alignment: .leading, spacing: 4) {
                    Text("コサイン類似度: \(NumberText.fixed(similarity, fractionDigits: 4))")
                        .font(.subheadline.weight(.semibold))
                    ProgressView(value: max(0, similarity))
                    Text("1 に近いほど意味が似ています（言語が違っても意味が同じなら高くなります）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("先頭 8 要素: " + result.preview.map { NumberText.fixed($0, fractionDigits: 4) }.joined(separator: ", "))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}
