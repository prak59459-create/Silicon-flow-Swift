import SwiftUI
import SiliconFlowKit

/// モデルの詳細：上部に要点、下に「試す」「詳細」タブ
struct ModelDetailView: View {
    let model: ModelDescriptor

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @State private var tab: DetailTab = .playground

    enum DetailTab: String, CaseIterable, Identifiable {
        case playground = "試す"
        case info = "詳細"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelSummaryBar(model: model)
            Picker("表示", selection: $tab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            Divider()
            tabContent
        }
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.id) {
            await store.fetchHuggingFaceIfNeeded(for: model.id, enabled: settings.useHuggingFace)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .playground:
            PlaygroundHost(model: model)
        case .info:
            ModelInfoView(model: model)
        }
    }
}

/// 価格・パラメータ数・コンテキスト長の要約
struct ModelSummaryBar: View {
    let model: ModelDescriptor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SummaryPill(title: "料金", value: model.priceText, systemImage: "yensign.circle", color: model.isFree ? .green : .orange)
                SummaryPill(title: "パラメータ", value: model.parameters?.displayText ?? "不明", systemImage: "cpu", color: .purple)
                SummaryPill(title: "コンテキスト", value: model.contextText, systemImage: "text.alignleft", color: .teal)
                SummaryPill(title: "種類", value: model.category.displayName, systemImage: model.category.systemImage, color: .blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.1)))
    }
}

/// カテゴリに応じた「試す」画面
struct PlaygroundHost: View {
    let model: ModelDescriptor
    @EnvironmentObject private var chats: ChatSessionRegistry

    var body: some View {
        switch model.category {
        case .chat, .vision, .other:
            ChatPlaygroundView(model: model, session: chats.session(for: model.id))
        case .embedding:
            EmbeddingPlaygroundView(model: model)
        case .reranker:
            RerankPlaygroundView(model: model)
        case .textToImage, .imageToImage:
            ImagePlaygroundView(model: model)
        case .textToSpeech:
            SpeechPlaygroundView(model: model)
        case .speechToText:
            TranscriptionPlaygroundView(model: model)
        case .textToVideo, .imageToVideo:
            VideoPlaygroundView(model: model)
        }
    }
}
