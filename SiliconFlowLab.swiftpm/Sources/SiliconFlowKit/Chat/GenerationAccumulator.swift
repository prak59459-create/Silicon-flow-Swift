import Foundation

/// ストリーミングのチャンクを集めて、回答・思考・使用量・速度をまとめます。
public struct GenerationAccumulator: Sendable {
    public private(set) var content = ""
    public private(set) var reasoning = ""
    public private(set) var finishReason: String?
    public private(set) var usage: Usage?
    public private(set) var model: String?
    public private(set) var chunkCount = 0
    public private(set) var metrics: GenerationMetrics

    public init(startedAt: TimeInterval) {
        metrics = GenerationMetrics(startedAt: startedAt)
    }

    /// チャンクを追加します。何か新しい文字が届いたら true。
    @discardableResult
    public mutating func apply(_ chunk: ChatCompletionChunk, at time: TimeInterval) -> Bool {
        chunkCount += 1
        if let model = chunk.model, !model.isEmpty { self.model = model }
        if let usage = chunk.usage { self.usage = usage }
        var changed = false
        if let reasoningDelta = chunk.primaryReasoning, !reasoningDelta.isEmpty {
            reasoning += reasoningDelta
            metrics.markFirstReasoningToken(at: time)
            changed = true
        }
        if let contentDelta = chunk.primaryContent, !contentDelta.isEmpty {
            content += contentDelta
            metrics.markFirstContentToken(at: time)
            if !reasoning.isEmpty { metrics.markReasoningEnded(at: time) }
            changed = true
        }
        if let reason = chunk.finishReason, !reason.isEmpty { finishReason = reason }
        return changed
    }

    public mutating func finish(at time: TimeInterval) {
        metrics.finishedAt = time
        if !reasoning.isEmpty, metrics.reasoningEndedAt == nil { metrics.reasoningEndedAt = time }
    }

    /// 出力トークン数（使用量が無ければ文字数から概算）
    public var completionTokensEstimate: Int {
        if let tokens = usage?.completionTokens { return tokens }
        return TokenEstimator.estimate(content) + TokenEstimator.estimate(reasoning)
    }

    /// 回答が出力上限で打ち切られたか
    public var wasTruncated: Bool { finishReason == "length" }

    /// 内容フィルタで止められたか
    public var wasFiltered: Bool { finishReason == "content_filter" }
}

/// 速度の計測（時間はすべて単調増加する秒数）
public struct GenerationMetrics: Sendable, Equatable, Codable {
    public var startedAt: TimeInterval
    public var firstTokenAt: TimeInterval?
    public var firstContentAt: TimeInterval?
    public var reasoningEndedAt: TimeInterval?
    public var finishedAt: TimeInterval?
    private var firstReasoningAt: TimeInterval?

    public init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    mutating func markFirstReasoningToken(at time: TimeInterval) {
        if firstReasoningAt == nil { firstReasoningAt = time }
        if firstTokenAt == nil { firstTokenAt = time }
    }

    mutating func markFirstContentToken(at time: TimeInterval) {
        if firstContentAt == nil { firstContentAt = time }
        if firstTokenAt == nil { firstTokenAt = time }
    }

    mutating func markReasoningEnded(at time: TimeInterval) {
        if reasoningEndedAt == nil { reasoningEndedAt = time }
    }

    /// 最初の 1 文字が届くまでの時間（TTFT）
    public var timeToFirstToken: TimeInterval? { firstTokenAt.map { max(0, $0 - startedAt) } }

    /// 全体の所要時間
    public var totalDuration: TimeInterval? { finishedAt.map { max(0, $0 - startedAt) } }

    /// 思考にかかった時間
    public var reasoningDuration: TimeInterval? {
        guard let start = firstReasoningAt else { return nil }
        let end = reasoningEndedAt ?? finishedAt
        return end.map { max(0, $0 - start) }
    }

    /// 出力速度（トークン/秒）。生成にかかった時間（最初の文字〜終了）で割ります。
    public func tokensPerSecond(completionTokens: Int) -> Double? {
        guard completionTokens > 0, let first = firstTokenAt, let finished = finishedAt else { return nil }
        let duration = finished - first
        guard duration > 0.05 else { return nil }
        return Double(completionTokens) / duration
    }
}

/// トークン数のおおまかな見積もり（使用量が返ってこないときの表示用）
public enum TokenEstimator {
    /// 英語は約 4 文字、日本語・中国語は約 1 文字で 1 トークンとして数えます。
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var asciiCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII { asciiCount += 1 } else { otherCount += 1 }
        }
        return Int((Double(asciiCount) / 4).rounded(.up)) + otherCount
    }
}
