import Foundation

/// モデル名・説明文からパラメータ数を読み取ります。
public enum ParameterCountParser {
    /// モデル ID から推定します。
    /// 例: "Qwen/Qwen3-235B-A22B" → 235B / アクティブ 22B、"Mixtral-8x7B" → 56B / MoE
    public static func parse(modelID: String) -> ParameterCount? {
        let name = ModelClassifier.shortName(of: modelID)
        let tokens = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
        var total: Double?
        var active: Double?
        for token in tokens {
            if let experts = parseExperts(token) {
                total = experts
                continue
            }
            if let value = parseActive(token) {
                active = value
                continue
            }
            if let value = parseSize(token) {
                total = value
            }
        }
        let result = ParameterCount(totalB: total, activeB: active)
        return result.isEmpty ? nil : result
    }

    /// 説明文から「総パラメータ・アクティブパラメータ」を探します（英語・中国語に対応）。
    /// 例: "397B total, 17B active" / "总参数量 1T，激活参数 32B"
    public static func parse(description: String?) -> ParameterCount? {
        guard let text = description, !text.isEmpty else { return nil }
        var total = firstMatch(in: text, patterns: [
            #"(\d+(?:\.\d+)?)\s*([BTbt])\s*(?:total|parameters? in total)"#,
            #"总参数(?:量)?(?:为|达)?\s*(\d+(?:\.\d+)?)\s*([BTbt亿])"#,
            #"total(?: of)?\s*(\d+(?:\.\d+)?)\s*([BTbt])"#,
        ])
        let active = firstMatch(in: text, patterns: [
            #"(\d+(?:\.\d+)?)\s*([BTbt])\s*(?:active|activated)"#,
            #"激活参数(?:量)?(?:为)?\s*(\d+(?:\.\d+)?)\s*([BTbt亿])"#,
            #"activat(?:es|ed|ing)?\s*(\d+(?:\.\d+)?)\s*([BTbt])"#,
        ])
        if total == nil, active == nil {
            total = firstMatch(in: text, patterns: [#"(\d+(?:\.\d+)?)\s*([BTbt])\s*(?:parameters?|params?|参数)"#])
        }
        let result = ParameterCount(totalB: total, activeB: active)
        return result.isEmpty ? nil : result
    }

    // MARK: - トークン単位の解析

    /// "8x7B" → 56
    static func parseExperts(_ token: String) -> Double? {
        let lower = token.lowercased()
        guard let xIndex = lower.firstIndex(of: "x"), lower.hasSuffix("b") else { return nil }
        let countText = lower[..<xIndex]
        let sizeText = lower[lower.index(after: xIndex)..<lower.index(before: lower.endIndex)]
        guard let count = Double(countText), let size = Double(sizeText), count >= 2, count <= 256 else { return nil }
        return count * size
    }

    /// "A22B" → 22
    static func parseActive(_ token: String) -> Double? {
        guard token.count >= 3, let first = token.first, first == "A" || first == "a" else { return nil }
        return parseSize(String(token.dropFirst()))
    }

    /// "7B" → 7, "1.5b" → 1.5, "560M" → 0.56, "1T" → 1000
    static func parseSize(_ token: String) -> Double? {
        guard let unit = token.last, token.count >= 2 else { return nil }
        let numberText = token.dropLast()
        guard numberText.first?.isNumber == true, let value = Double(numberText), value > 0 else { return nil }
        switch unit {
        case "B", "b": return value <= 5000 ? value : nil
        case "T", "t": return value <= 20 ? value * 1000 : nil
        case "M", "m": return value >= 10 ? value / 1000 : nil
        default: return nil
        }
    }

    private static func firstMatch(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange])
            else { continue }
            switch text[unitRange].lowercased() {
            case "t": return number * 1000
            case "亿": return number / 10
            default: return number
            }
        }
        return nil
    }
}
