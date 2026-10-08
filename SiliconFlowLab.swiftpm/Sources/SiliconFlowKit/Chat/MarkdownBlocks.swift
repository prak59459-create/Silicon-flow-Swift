import Foundation

/// 回答のテキストを「文章」と「コードブロック」に分けたもの（表示用）
public enum MarkdownBlock: Hashable, Sendable {
    case text(String)
    case code(language: String?, code: String, isClosed: Bool)
}

public enum MarkdownBlockParser {
    /// ``` / ~~~ で囲まれた部分をコードブロックにします。閉じられていない（生成途中の）ブロックにも対応。
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var textLines: [Substring] = []
        var codeLines: [Substring] = []
        var language: String?
        var fenceCharacter: Character?

        func flushText() {
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(.text(text)) }
            textLines.removeAll()
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceCharacter {
                if isClosingFence(trimmed, character: fence) {
                    blocks.append(.code(language: language, code: codeLines.joined(separator: "\n"), isClosed: true))
                    fenceCharacter = nil
                    language = nil
                    codeLines.removeAll()
                } else {
                    codeLines.append(line)
                }
            } else if let fence = openingFence(trimmed) {
                flushText()
                fenceCharacter = fence
                let info = trimmed.drop(while: { $0 == fence }).trimmingCharacters(in: .whitespaces)
                language = info.split(separator: " ").first.map(String.init)
            } else {
                textLines.append(line)
            }
        }
        if fenceCharacter != nil {
            blocks.append(.code(language: language, code: codeLines.joined(separator: "\n"), isClosed: false))
        } else {
            flushText()
        }
        return blocks
    }

    /// インライン Markdown 表示用の前処理。見出しを太字に、箇条書きを「•」にします
    /// （SwiftUI の Text はインライン記法しか描画できないため）。
    public static func inlineFriendly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine -> String in
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = String(line.prefix { $0 == " " })
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, trimmed.count - title.count <= 7 { return "**\(title)**" }
            }
            for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
                return indent + "• " + String(trimmed.dropFirst(marker.count))
            }
            if trimmed == "---" || trimmed == "***" { return "──────────" }
            return line
        }.joined(separator: "\n")
    }

    private static func openingFence(_ line: String) -> Character? {
        if line.hasPrefix("```") { return "`" }
        if line.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func isClosingFence(_ line: String, character: Character) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == character }
    }
}
