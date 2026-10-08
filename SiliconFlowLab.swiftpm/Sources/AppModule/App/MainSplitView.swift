import SwiftUI
import SiliconFlowKit

/// iPad では 3 列（サイドバー / モデル一覧 / 詳細）、iPhone では画面遷移で表示します。
struct MainSplitView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: ModelStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } content: {
            ModelListView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        if let model = store.model(id: router.selectedModelID) {
            ModelDetailView(model: model)
                .id(model.id)
        } else {
            NoSelectionView()
        }
    }
}

/// モデル未選択時の案内
private struct NoSelectionView: View {
    var body: some View {
        ContentUnavailableView {
            Label("モデルを選んでください", systemImage: "sparkles")
        } description: {
            Text("左の一覧からモデルを選ぶと、価格・パラメータ数を確認して、その場で試せます。")
        }
    }
}
