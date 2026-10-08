import SwiftUI
import SiliconFlowKit

/// 回答の Markdown を表示します（文章はインライン記法、コードはブロック表示）。
struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlockParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .text(let text):
            MarkdownTextView(text: text)
        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code)
        }
    }
}

private struct MarkdownTextView: View {
    let text: String

    var body: some View {
        Text(Self.attributed(text))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(_ text: String) -> AttributedString {
        let prepared = MarkdownBlockParser.inlineFriendly(text)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: prepared, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}

/// コードブロック（横スクロール・コピーボタン付き）
struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: code, showsTitle: false)
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .tertiarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .separator)))
    }
}
