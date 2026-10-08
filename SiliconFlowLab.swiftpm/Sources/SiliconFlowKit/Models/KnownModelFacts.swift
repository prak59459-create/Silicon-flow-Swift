import Foundation

/// 名前から分からない有名 MoE モデルのパラメータ数（公開情報）。
///
/// オンラインの情報源がすべて使えないときの最後の予備です。小さな表に留めて、
/// コンパイル時間に影響しないようにしています。
public enum KnownModelFacts {
    struct Fact {
        let prefix: String
        let totalB: Double
        let activeB: Double?
    }

    /// 前方一致（小文字、"Pro/" 除去後）。一番長く一致したものを使います。
    /// totalB が 0 の行は「この接頭辞は別物なので推定しない」ための除外指定です
    /// （例: DeepSeek-R1 の蒸留版は R1 本体とはサイズが全く違う）。
    static let facts: [Fact] = [
        Fact(prefix: "deepseek-ai/deepseek-r1-distill", totalB: 0, activeB: nil),
        Fact(prefix: "deepseek-ai/deepseek-r1-0528-qwen3", totalB: 0, activeB: nil),
        Fact(prefix: "deepseek-ai/deepseek-v3", totalB: 671, activeB: 37),
        Fact(prefix: "deepseek-ai/deepseek-r1", totalB: 671, activeB: 37),
        Fact(prefix: "moonshotai/kimi-k2", totalB: 1000, activeB: 32),
        Fact(prefix: "zai-org/glm-4.5-air", totalB: 106, activeB: 12),
        Fact(prefix: "zai-org/glm-4.5v", totalB: 106, activeB: 12),
        Fact(prefix: "zai-org/glm-4.6v", totalB: 106, activeB: 12),
        Fact(prefix: "zai-org/glm-4.5", totalB: 355, activeB: 32),
        Fact(prefix: "zai-org/glm-4.6", totalB: 355, activeB: 32),
        Fact(prefix: "minimaxai/minimax-m2", totalB: 230, activeB: 10),
        Fact(prefix: "openai/gpt-oss-120b", totalB: 117, activeB: 5.1),
        Fact(prefix: "openai/gpt-oss-20b", totalB: 21, activeB: 3.6),
        Fact(prefix: "inclusionai/ling-flash-2.0", totalB: 100, activeB: 6.1),
        Fact(prefix: "inclusionai/ring-flash-2.0", totalB: 100, activeB: 6.1),
        Fact(prefix: "inclusionai/ling-mini-2.0", totalB: 16, activeB: 1.4),
        Fact(prefix: "tencent/hunyuan-a13b", totalB: 80, activeB: 13),
        Fact(prefix: "stepfun-ai/step3", totalB: 321, activeB: 38),
    ]

    public static func parameters(for modelID: String) -> ParameterCount? {
        let id = ModelClassifier.strippedPrefixes(modelID).lowercased()
        let match = facts
            .filter { id.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }
        guard let match, match.totalB > 0 else { return nil }
        return ParameterCount(totalB: match.totalB, activeB: match.activeB)
    }
}
