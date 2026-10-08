import SwiftUI
import SiliconFlowKit

/// リランクモデルを試す：質問に関係の深い順に文書を並べ替える
struct RerankPlaygroundView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var runner = RequestRunner<[RankedDocument]>()
    @State private var query = "Apple"
    @State private var documentsText = "apple（りんご）は果物です\nバナナは黄色い果物です\nApple は iPhone を作っている会社です\n今日はいい天気です"

    struct RankedDocument: Identifiable {
        let id: Int
        let rank: Int
        let text: String
        let score: Double
    }

    var body: some View {
        PlaygroundScroll {
            PlaygroundCard(title: "質問", systemImage: "magnifyingglass") {
                TextField("検索したい内容", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            PlaygroundCard(title: "文書（1 行に 1 つ）", systemImage: "doc.text") {
                InputEditor(placeholder: "文書を改行で区切って入力", text: $documentsText, minHeight: 120)
                Text("\(documents.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            RunButton(title: "関連度で並べ替え", systemImage: "list.number", isRunning: runner.isRunning, isDisabled: isInputInvalid, note: PriceNote.text(for: model), action: { run() }, cancel: { runner.cancel() })
            if let error = runner.error {
                ErrorCardView(error: error, retry: { run() }, dismiss: { runner.dismissError() })
            }
            if let ranked = runner.output {
                PlaygroundCard(title: "結果", systemImage: "checkmark.circle") {
                    ForEach(ranked) { document in
                        RankedRow(document: document)
                    }
                }
            }
        }
    }

    private var documents: [String] {
        documentsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var isInputInvalid: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty || documents.isEmpty
    }

    private func run() {
        let client = settings.makeClient()
        let docs = documents
        let request = RerankRequest(model: model.id, query: query, documents: docs, topN: docs.count, returnDocuments: true)
        runner.run(region: client.region, modelID: model.id) {
            let response = try await client.rerank(request)
            return response.ranked.enumerated().map { offset, result in
                let text = result.document?.text ?? (docs.indices.contains(result.index) ? docs[result.index] : "")
                return RankedDocument(id: result.index, rank: offset + 1, text: text, score: result.relevanceScore)
            }
        }
    }
}

private struct RankedRow: View {
    let document: RerankPlaygroundView.RankedDocument

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(document.rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.text)
                    .font(.subheadline)
                ProgressView(value: min(1, max(0, document.score)))
                Text("スコア \(NumberText.fixed(document.score, fractionDigits: 4))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
