import SwiftUI
import SiliconFlowKit

/// 回答の速度・トークン数・料金
struct MessageMetricsView: View {
    let turn: ChatTurn
    let rates: ExchangeRates?

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 4) {
            ForEach(items, id: \.text) { item in
                Label(item.text, systemImage: item.icon)
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private struct Item {
        let text: String
        let icon: String
    }

    private var items: [Item] {
        var result: [Item] = []
        if let metrics = turn.metrics {
            if let ttft = metrics.timeToFirstToken {
                result.append(Item(text: "最初の応答 \(DisplayFormat.duration(ttft))", icon: "timer"))
            }
            if let total = metrics.totalDuration {
                result.append(Item(text: "合計 \(DisplayFormat.duration(total))", icon: "clock"))
            }
            if let completion = turn.usage?.completionTokens, let speed = metrics.tokensPerSecond(completionTokens: completion) {
                result.append(Item(text: "\(NumberText.fixed(speed, fractionDigits: 1)) トークン/秒", icon: "speedometer"))
            }
        }
        if let usage = turn.usage {
            result.append(Item(text: tokenText(usage), icon: "number"))
        }
        if let cost = turn.cost {
            let prefix = turn.usageIsEstimated == true ? "約 " : ""
            result.append(Item(text: prefix + DisplayFormat.money(cost, rates: rates, showYen: rates != nil), icon: "yensign.circle"))
        }
        return result
    }

    private func tokenText(_ usage: Usage) -> String {
        let prefix = turn.usageIsEstimated == true ? "約 " : ""
        var text = prefix + "入力 \(DisplayFormat.tokens(usage.promptTokens ?? 0)) / 出力 \(DisplayFormat.tokens(usage.completionTokens ?? 0))"
        if let reasoning = usage.reasoningTokens, reasoning > 0 {
            text += "（思考 \(DisplayFormat.tokens(reasoning))）"
        }
        return text
    }
}
