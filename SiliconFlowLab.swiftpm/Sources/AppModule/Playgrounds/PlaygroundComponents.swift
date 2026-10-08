import SwiftUI
import SiliconFlowKit

/// 「試す」画面の共通の入れ物（スクロール・余白）
struct PlaygroundScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// 見出し付きのカード
struct PlaygroundCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

/// 複数行の入力欄（枠付き）
struct InputEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .separator)))
    }
}

/// 実行ボタン（実行中はキャンセルボタンに変わります）
struct RunButton: View {
    let title: String
    let systemImage: String
    let isRunning: Bool
    var isDisabled: Bool = false
    var note: String?
    let action: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: action) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: systemImage)
                        }
                        Text(isRunning ? "実行中…" : title)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || isDisabled)
                if isRunning {
                    Button("キャンセル", role: .cancel, action: cancel)
                        .buttonStyle(.bordered)
                }
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 価格の目安（実行前に表示）
enum PriceNote {
    static func text(for model: ModelDescriptor) -> String {
        if model.isFree { return "このモデルは無料です。" }
        guard let entry = model.catalog, entry.hasPrice else { return "価格情報がありません。公式サイトで確認してください。" }
        return "料金の目安: \(PriceFormatter.compact(entry))（\((entry.unit ?? .perMillionTokens).displayName)）"
    }
}

/// 結果の 1 項目（ラベルと値）
struct ResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .textSelection(.enabled)
        }
        .frame(minWidth: 90, alignment: .leading)
    }
}
