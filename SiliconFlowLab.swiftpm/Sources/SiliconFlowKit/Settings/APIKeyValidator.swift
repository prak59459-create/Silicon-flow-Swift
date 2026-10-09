import Foundation

/// API キーの入力チェック（通信する前に分かる間違いを指摘します）。
public enum APIKeyValidator {
    public enum Issue: String, Sendable, Equatable, CaseIterable {
        case empty
        case containsWhitespace
        case unexpectedPrefix
        case tooShort
        case containsNonASCII

        public var message: String {
            switch self {
            case .empty: return "API キーが空です。"
            case .containsWhitespace: return "キーの途中に空白または改行が含まれています。コピーし直してください。"
            case .unexpectedPrefix: return "SiliconFlow のキーは通常「sk-」で始まります。別のサービスのキーではありませんか？"
            case .tooShort: return "キーが短すぎます。途中までしかコピーされていない可能性があります。"
            case .containsNonASCII: return "キーに全角文字や記号が含まれています。半角英数字だけのはずです。"
            }
        }

        /// 送信を止めるべき致命的な問題か（警告だけで送信してよいものは false）
        public var isBlocking: Bool {
            switch self {
            case .empty, .containsWhitespace, .containsNonASCII: return true
            case .unexpectedPrefix, .tooShort: return false
            }
        }
    }

    public struct Result: Sendable, Equatable {
        public var sanitizedKey: String
        public var issues: [Issue]

        public var isUsable: Bool { !issues.contains { $0.isBlocking } }
        public var warnings: [Issue] { issues.filter { !$0.isBlocking } }
    }

    /// 前後の空白・不可視文字・「Bearer 」・引用符・全角を取り除きます。
    public static func sanitize(_ raw: String) -> String {
        var key = TextSanitizer.trimmed(TextSanitizer.halfWidth(raw))
        let lowered = key.lowercased()
        if lowered.hasPrefix("authorization:") {
            key = TextSanitizer.trimmed(String(key.dropFirst("authorization:".count)))
        }
        if key.lowercased().hasPrefix("bearer ") {
            key = TextSanitizer.trimmed(String(key.dropFirst("bearer ".count)))
        }
        let quotes: Set<Character> = ["\"", "'", "“", "”", "‘", "’", "`", "「", "」"]
        while let first = key.first, quotes.contains(first) { key.removeFirst() }
        while let last = key.last, quotes.contains(last) { key.removeLast() }
        return TextSanitizer.trimmed(key)
    }

    public static func validate(_ raw: String) -> Result {
        let key = sanitize(raw)
        var issues: [Issue] = []
        if key.isEmpty {
            return Result(sanitizedKey: key, issues: [.empty])
        }
        if key.contains(where: { $0.isWhitespace || $0.isNewline }) {
            issues.append(.containsWhitespace)
        }
        if !key.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 0x21 && $0.value <= 0x7E }) {
            issues.append(.containsNonASCII)
        }
        if !key.lowercased().hasPrefix("sk-") {
            issues.append(.unexpectedPrefix)
        }
        if key.count < 20 {
            issues.append(.tooShort)
        }
        return Result(sanitizedKey: key, issues: issues)
    }
}
