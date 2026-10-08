import Foundation

/// 文字列のクリーニング処理。
public enum TextSanitizer {
    /// 目に見えない文字（ゼロ幅スペース、BOM、制御文字など）。
    static let invisibleScalars: Set<UInt32> = [
        0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD,
    ]

    /// 前後の空白・改行・全角スペース・不可視文字を取り除きます。
    public static func trimmed(_ text: String) -> String {
        let cleaned = removingInvisibles(text)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}")))
    }

    /// 不可視文字を取り除きます。
    public static func removingInvisibles(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !invisibleScalars.contains(scalar.value) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// 全角英数字・記号を半角に変換します（例: "ｓｋ－" → "sk-"）。
    public static func halfWidth(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value >= 0xFF01, value <= 0xFF5E, let converted = Unicode.Scalar(value - 0xFEE0) {
                scalars.append(converted)
            } else if value == 0x3000 {
                scalars.append(" ")
            } else if value == 0x2010 || value == 0x2011 || value == 0x2012 || value == 0x2013 || value == 0x2212 {
                // ハイフンに似た文字（‐ ‑ ‒ – −）
                scalars.append("-")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 長い文字列を先頭 `limit` 文字に切り詰めます。
    public static func snippet(_ text: String, limit: Int = 300) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// HTML らしい文字列かどうか（キャプティブポータルや誤った URL の検出用）。
    public static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.prefix(512).lowercased()
        return head.contains("<!doctype html") || head.contains("<html") || head.contains("<head") || head.contains("<body")
    }

    /// API キーなど秘密の値を伏せ字にします（例: sk-abcd…wxyz）。
    public static func masked(_ secret: String) -> String {
        let value = trimmed(secret)
        guard value.count > 10 else { return String(repeating: "•", count: max(4, value.count)) }
        return String(value.prefix(5)) + "••••" + String(value.suffix(4))
    }
}
