import SwiftUI
import SiliconFlowKit

/// 一覧の 1 行：名前・価格・パラメータ数・コンテキスト長・特徴
struct ModelRowView: View {
    let model: ModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleLine
            detailLine
        }
        .padding(.vertical, 4)
        .opacity(model.isDeprecated ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: model.category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text(model.displayName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(model.priceText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.isFree ? Color.green : Color.secondary)
                .lineLimit(1)
        }
    }

    private var detailLine: some View {
        HStack(spacing: 6) {
            if let organization = model.organization {
                Text(organization)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let parameters = model.parameters {
                Badge(text: parameters.compactText, systemImage: "cpu", color: .purple)
            }
            if model.catalog?.contextLength != nil {
                Badge(text: model.contextText, systemImage: "text.alignleft", color: .teal)
            }
            ModelFeatureBadges(model: model, limit: 3)
            Spacer(minLength: 0)
        }
    }
}

/// 無料・Pro・画像入力・思考・提供終了 などのバッジ
struct ModelFeatureBadges: View {
    let model: ModelDescriptor
    var limit: Int = 10

    var body: some View {
        ForEach(Array(features.prefix(limit)), id: \.text) { feature in
            Badge(text: feature.text, systemImage: feature.icon, color: feature.color)
        }
    }

    struct Feature {
        let text: String
        let icon: String?
        let color: Color
    }

    var features: [Feature] {
        var result: [Feature] = []
        if model.isDeprecated || model.catalog?.deprecationDate != nil {
            result.append(Feature(text: "提供終了予定", icon: "clock.badge.exclamationmark", color: .red))
        }
        if model.isFree { result.append(Feature(text: "無料", icon: nil, color: .green)) }
        if model.isPro { result.append(Feature(text: "Pro", icon: nil, color: .orange)) }
        if model.has(.vision) && model.category != .vision {
            result.append(Feature(text: "画像入力", icon: "eye", color: .blue))
        }
        if model.has(.reasoning) { result.append(Feature(text: "思考", icon: "brain", color: .pink)) }
        if model.has(.tools) { result.append(Feature(text: "ツール", icon: "wrench.and.screwdriver", color: .indigo)) }
        if !model.isListedByAPI { result.append(Feature(text: "未確認", icon: "questionmark", color: .gray)) }
        return result
    }
}
