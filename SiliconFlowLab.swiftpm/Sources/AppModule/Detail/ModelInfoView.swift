import SwiftUI
import SiliconFlowKit

/// モデルの詳しい情報（価格・規模・機能・出どころ・リンク）
struct ModelInfoView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        List {
            BasicInfoSection(model: model)
            PriceSection(model: model, rates: store.exchangeRates, showYen: settings.showYen)
            ScaleSection(model: model)
            if !model.capabilities.isEmpty {
                CapabilitySection(capabilities: model.capabilities)
            }
            if let summary = model.catalog?.summary {
                Section("説明") {
                    Text(summary)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
            if let info = store.huggingFace[model.id] {
                HuggingFaceSection(info: info)
            }
            LinksSection(model: model, region: settings.region, huggingFace: store.huggingFace[model.id])
        }
        .listStyle(.insetGrouped)
    }
}

private struct BasicInfoSection: View {
    let model: ModelDescriptor

    var body: some View {
        Section("基本情報") {
            HStack {
                Text(model.id)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                Spacer()
                CopyButton(text: model.id, showsTitle: false)
                    .buttonStyle(.borderless)
            }
            InfoRow(title: "種類", value: model.category.displayName, footnote: categoryNote)
            if let organization = model.organization {
                InfoRow(title: "開発元", value: organization)
            }
            if let date = model.catalog?.releaseDate {
                InfoRow(title: "公開日", value: date)
            }
            if let date = model.catalog?.deprecationDate {
                InfoRow(title: "提供終了日", value: date, footnote: "この日以降は使えなくなります")
            }
            if !model.isListedByAPI {
                Text("このモデルはあなたの API キーのモデル一覧に含まれていません（公開カタログの情報です）。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var categoryNote: String {
        switch model.categorySource {
        case .api: return "SiliconFlow API の分類"
        case .catalog: return "公開カタログの分類"
        case .heuristic: return "モデル名から推定"
        }
    }
}

private struct PriceSection: View {
    let model: ModelDescriptor
    let rates: ExchangeRates?
    let showYen: Bool

    var body: some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                InfoRow(title: row.0, value: row.1)
            }
            if model.catalog?.requiresChargedBalance == true {
                Label("無料クレジット（贈与残高）では使えず、チャージした残高が必要です", systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.catalog?.requiresRealName == true {
                Label("利用には実名認証が必要です", systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.isPro {
                Text("「Pro/」版は高速・安定な有料版です。通常版と価格が異なります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("料金")
        } footer: {
            Text(sourceText)
        }
    }

    private var rows: [(String, String)] {
        PriceFormatter.detailRows(model.catalog, rates: rates, showYen: showYen)
    }

    private var sourceText: String {
        var parts: [String] = []
        if let source = model.catalog?.priceSource { parts.append("出どころ: \(source)") }
        if let currency = model.catalog?.currency { parts.append("通貨: \(currency.displayName)") }
        if showYen, let rates { parts.append("円換算: \(rates.source)") }
        return parts.isEmpty ? "価格情報が見つかりませんでした。公式サイトで確認してください。" : parts.joined(separator: " ・ ")
    }
}

private struct ScaleSection: View {
    let model: ModelDescriptor

    var body: some View {
        Section("規模") {
            InfoRow(title: "パラメータ数", value: model.parameters?.displayText ?? "不明", footnote: model.parametersSource.map { "出どころ: \($0)" })
            if let context = model.catalog?.contextLength {
                InfoRow(title: "コンテキスト長", value: "\(ContextLengthFormatter.format(context))（\(DisplayFormat.tokens(context)) トークン）")
            }
            if let output = model.catalog?.maxOutputTokens {
                InfoRow(title: "最大出力", value: "\(DisplayFormat.tokens(output)) トークン")
            }
            if model.parameters?.isMoE == true {
                Text("MoE（専門家混合）モデルです。総パラメータのうち、1 トークンの計算に使うのはアクティブ分だけなので、規模の割に高速・安価です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CapabilitySection: View {
    let capabilities: [ModelCapability]

    var body: some View {
        Section("機能") {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(capabilities, id: \.self) { capability in
                    Badge(text: capability.displayName, systemImage: capability.systemImage, color: .indigo)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct HuggingFaceSection: View {
    let info: HuggingFaceClient.ModelInfo

    var body: some View {
        Section("Hugging Face") {
            InfoRow(title: "リポジトリ", value: info.repoID)
            if let count = info.totalParameters {
                InfoRow(title: "実パラメータ数", value: DisplayFormat.tokens(Int(clamping: count)))
            }
            if let license = info.license {
                InfoRow(title: "ライセンス", value: license)
            }
            if let downloads = info.downloads {
                InfoRow(title: "ダウンロード数", value: DisplayFormat.tokens(downloads))
            }
            if let likes = info.likes {
                InfoRow(title: "いいね", value: DisplayFormat.tokens(likes))
            }
        }
    }
}

private struct LinksSection: View {
    let model: ModelDescriptor
    let region: APIRegion
    let huggingFace: HuggingFaceClient.ModelInfo?

    var body: some View {
        Section("リンク") {
            Link(destination: region.modelsPageURL) {
                Label("SiliconFlow のモデル一覧", systemImage: "square.grid.2x2")
            }
            Link(destination: region.pricingPageURL) {
                Label("公式の料金ページ", systemImage: "yensign.circle")
            }
            if let url = huggingFace?.pageURL ?? fallbackHuggingFaceURL {
                Link(destination: url) {
                    Label("Hugging Face のモデルページ", systemImage: "face.smiling")
                }
            }
        }
    }

    private var fallbackHuggingFaceURL: URL? {
        guard let repo = HuggingFaceClient.candidateRepoIDs(for: model.id).first else { return nil }
        return URL(string: "https://huggingface.co/\(repo)")
    }
}
