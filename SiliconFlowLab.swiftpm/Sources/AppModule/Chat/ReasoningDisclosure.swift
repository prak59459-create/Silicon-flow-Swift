import SwiftUI

/// 思考（推論）過程の折りたたみ表示
struct ReasoningDisclosure: View {
    let text: String
    let duration: TimeInterval?
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(title, systemImage: "brain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.pink)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.pink.opacity(0.06)))
        .onAppear { isExpanded = isStreaming }
    }

    private var title: String {
        if isStreaming { return "思考中…（\(text.count) 文字）" }
        if let duration { return "思考過程（\(DisplayFormat.duration(duration))）" }
        return "思考過程"
    }
}
