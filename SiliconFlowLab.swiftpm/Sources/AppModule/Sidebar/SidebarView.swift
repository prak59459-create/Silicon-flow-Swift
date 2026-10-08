import SwiftUI
import SiliconFlowKit

/// サイドバー：アカウント・カテゴリ・ツール
struct SidebarView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        List(selection: $router.sidebarSelection) {
            Section {
                BalanceCard()
            }
            Section("モデル") {
                SidebarRow(item: .all, count: store.models.count)
                SidebarRow(item: .free, count: freeCount)
            }
            Section("種類") {
                ForEach(availableCategories) { category in
                    SidebarRow(item: .category(category), count: counts[category] ?? 0)
                }
            }
            Section("ツール") {
                ToolButton(title: "接続診断", systemImage: "stethoscope") { router.show(.diagnostics) }
                ToolButton(title: "設定", systemImage: "gearshape") { router.show(.settings) }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SiliconFlow Lab")
    }

    private var counts: [ModelCategory: Int] { ModelQuery.counts(store.models) }

    private var freeCount: Int { store.models.filter(\.isFree).count }

    private var availableCategories: [ModelCategory] {
        let present = counts
        return ModelCategory.allCases.filter { (present[$0] ?? 0) > 0 }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let count: Int

    var body: some View {
        NavigationLink(value: item) {
            HStack {
                Label(item.title, systemImage: item.systemImage)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}
