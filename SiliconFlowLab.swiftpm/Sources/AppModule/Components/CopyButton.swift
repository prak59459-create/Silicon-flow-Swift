import SwiftUI
import UIKit

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

/// 押すとクリップボードにコピーし、少しの間「コピーしました」と表示するボタン
struct CopyButton: View {
    let text: String
    var title: String = "コピー"
    var showsTitle: Bool = true

    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            if showsTitle {
                Label(copied ? "コピーしました" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .accessibilityLabel(copied ? "コピーしました" : title)
    }

    private func copy() {
        Clipboard.copy(text)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
