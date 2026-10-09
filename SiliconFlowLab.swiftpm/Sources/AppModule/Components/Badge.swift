import SwiftUI

/// 小さなラベル（無料・VLM・思考 など）
struct Badge: View {
    let text: String
    var systemImage: String?
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// 情報の 1 行（左にラベル、右に値）
struct InfoRow: View {
    let title: String
    let value: String
    var systemImage: String?
    var footnote: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            label
                .frame(minWidth: 110, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        } else {
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
