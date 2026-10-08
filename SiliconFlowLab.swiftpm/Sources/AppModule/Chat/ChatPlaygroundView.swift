import SwiftUI
import SiliconFlowKit

/// チャットで試す画面（画像理解モデルでは画像も添付できます）
struct ChatPlaygroundView: View {
    let model: ModelDescriptor
    @ObservedObject var session: ChatSession

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            ChatMessageList(model: model, session: session, retry: { retry() })
            Divider()
            ChatInputBar(session: session, allowsImages: allowsImages, onSend: { send() })
        }
        .toolbar { toolbarContent }
    }

    private var allowsImages: Bool {
        model.category == .vision || model.has(.vision)
    }

    private func send() {
        session.send(settings: settings, entry: model.catalog)
    }

    private func retry() {
        session.retry(settings: settings, entry: model.catalog)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                router.show(.chatParameters)
            } label: {
                Label("チャットの設定", systemImage: "slider.horizontal.3")
            }
            Menu {
                Button {
                    session.clear()
                } label: {
                    Label("新しい会話", systemImage: "square.and.pencil")
                }
                .disabled(!session.hasConversation)
                Button {
                    retry()
                } label: {
                    Label("最後の回答を作り直す", systemImage: "arrow.clockwise")
                }
                .disabled(session.isGenerating || !session.hasConversation)
                ShareLink(item: ChatTranscript.markdown(turns: session.turns, model: model.id)) {
                    Label("会話を共有", systemImage: "square.and.arrow.up")
                }
                .disabled(!session.hasConversation)
            } label: {
                Label("その他", systemImage: "ellipsis.circle")
            }
        }
    }
}

/// メッセージの一覧（新しいメッセージに自動でスクロール）
///
/// 型チェックを軽くするため、スクロール制御と中身を別の View に分けています。
private struct ChatMessageList: View {
    let model: ModelDescriptor
    @ObservedObject var session: ChatSession
    let retry: () -> Void

    var body: some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView {
                ChatMessageStack(model: model, session: session, retry: retry)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: session.turns.count) { scrollToBottom(proxy) }
            .onChange(of: session.liveContent) { scrollToBottom(proxy) }
            .onChange(of: session.lastError) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(ChatMessageStack.bottomID, anchor: .bottom)
    }
}

/// メッセージを縦に並べた中身
private struct ChatMessageStack: View {
    static let bottomID = "bottom"

    let model: ModelDescriptor
    @ObservedObject var session: ChatSession
    let retry: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if session.turns.isEmpty {
                ChatEmptyState(model: model) { prompt in session.draft = prompt }
            }
            ForEach(session.turns) { turn in
                bubble(for: turn)
            }
            if let error = session.lastError {
                ErrorCardView(error: error, retry: retry, dismiss: { session.dismissError() })
            }
            Color.clear
                .frame(height: 1)
                .id(Self.bottomID)
        }
        .padding()
    }

    private var rates: ExchangeRates? {
        settings.showYen ? store.exchangeRates : nil
    }

    private func bubble(for turn: ChatTurn) -> some View {
        let isStreaming: Bool = turn.state == .streaming
        let bubble = MessageBubble(
            turn: turn,
            liveContent: isStreaming ? session.liveContent : nil,
            liveReasoning: isStreaming ? session.liveReasoning : nil,
            rates: rates
        )
        return bubble.equatable().id(turn.id)
    }
}

/// 会話が空のときの案内とお試しプロンプト
private struct ChatEmptyState: View {
    let model: ModelDescriptor
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(model.displayName) と話してみましょう", systemImage: "sparkles")
                .font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(prompt) { onPick(prompt) }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.06)))
    }

    private var hint: String {
        if model.category == .vision || model.has(.vision) {
            return "左下の画像ボタンで写真を添付して質問できます。料金は入力・出力のトークン数で決まります。"
        }
        if model.has(.reasoning) {
            return "思考（推論）モデルです。回答の前に考えた過程も表示されます。"
        }
        return "下の例をタップするか、自由に質問を入力してください。"
    }

    private var prompts: [String] {
        if model.category == .vision || model.has(.vision) {
            return ["この画像に写っているものを説明して", "画像の文字を書き起こして"]
        }
        return ["自己紹介をしてください", "Swift の async/await を初心者向けに説明して", "日本の首都はどこ？一言で答えて", "1から10までの素数を挙げて、理由も説明して"]
    }
}
