import SwiftUI
import SiliconFlowKit

/// 会話の 1 メッセージ
///
/// Equatable にしているのは、生成中に画面が頻繁に更新されても、
/// 内容の変わっていない過去のメッセージ（Markdown の整形を含む）を描き直さないためです。
struct MessageBubble: View, Equatable {
    let turn: ChatTurn
    /// 生成中の文字（生成中のメッセージだけ）
    let liveContent: String?
    let liveReasoning: String?
    let rates: ExchangeRates?

    static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.turn == rhs.turn && lhs.liveContent == rhs.liveContent && lhs.liveReasoning == rhs.liveReasoning && lhs.rates == rhs.rates
    }

    var body: some View {
        switch turn.role {
        case .user:
            UserBubble(turn: turn)
        case .assistant, .system:
            AssistantBubble(turn: turn, liveContent: liveContent, liveReasoning: liveReasoning, rates: rates)
        }
    }
}

@MainActor
private struct UserBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 6) {
                if !turn.imageDataURLs.isEmpty {
                    AttachedImagesView(dataURLs: turn.imageDataURLs)
                }
                if !turn.content.isEmpty {
                    Text(turn.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
                }
            }
        }
        .contextMenu {
            Button {
                Clipboard.copy(turn.content)
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
        }
    }
}

@MainActor
private struct AssistantBubble: View {
    let turn: ChatTurn
    let liveContent: String?
    let liveReasoning: String?
    let rates: ExchangeRates?

    private var isStreaming: Bool { turn.state == .streaming }
    private var content: String { liveContent ?? turn.content }
    private var reasoning: String { liveReasoning ?? turn.reasoning }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !reasoning.isEmpty {
                ReasoningDisclosure(text: reasoning, duration: turn.metrics?.reasoningDuration, isStreaming: isStreaming && content.isEmpty)
            }
            messageText(content)
            notices
            if !isStreaming {
                MessageMetricsView(turn: turn, rates: rates)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .contextMenu { bubbleMenu }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text(ModelClassifier.shortName(of: turn.model ?? ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private func messageText(_ text: String) -> some View {
        if isStreaming {
            // 生成中は軽いプレーンテキストで表示し、完了後に Markdown として整形します
            Text(text.isEmpty ? (reasoning.isEmpty ? "考えています…" : "") : text)
                .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !text.isEmpty {
            MarkdownContentView(text: text)
        } else if turn.state == .failed {
            Text("回答を受け取れませんでした")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if turn.finishReason == "length" {
            Label("最大トークン数に達したため、回答が途中で終わっています。設定で最大トークン数を増やせます。", systemImage: "text.badge.xmark")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if turn.finishReason == "content_filter" {
            Label("安全フィルタにより回答が止められました。", systemImage: "hand.raised")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if turn.state == .cancelled {
            Label("途中で停止しました", systemImage: "stop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let errorTitle = turn.errorTitle {
            Label(errorTitle, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var bubbleMenu: some View {
        Button {
            Clipboard.copy(content)
        } label: {
            Label("回答をコピー", systemImage: "doc.on.doc")
        }
        if !reasoning.isEmpty {
            Button {
                Clipboard.copy(reasoning)
            } label: {
                Label("思考過程をコピー", systemImage: "brain")
            }
        }
    }
}

/// 添付画像のサムネイル
struct AttachedImagesView: View {
    let dataURLs: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(dataURLs.enumerated()), id: \.offset) { _, url in
                if let image = ImageEncoder.image(fromDataURL: url) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}
