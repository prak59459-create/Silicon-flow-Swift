import SwiftUI
import SiliconFlowKit

/// モデル一覧（検索・並べ替え・絞り込み）
struct ModelListView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var sort: ModelQuery.Sort = .recommended
    @State private var showsCatalogStatus = false

    var body: some View {
        List(selection: $router.selectedModelID) {
            ModelListBanners(showsCatalogStatus: $showsCatalogStatus)
            ForEach(visibleModels) { model in
                ModelRowView(model: model)
                    .tag(model.id)
            }
        }
        .listStyle(.plain)
        .overlay { placeholder }
        .searchable(text: $searchText, prompt: "モデル名・組織・タグで検索")
        .refreshable { await store.reloadAndWait(settings: settings) }
        .navigationTitle(router.sidebarSelection?.title ?? "モデル")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showsCatalogStatus) {
            CatalogStatusView()
                .environmentObject(store)
                .environmentObject(settings)
        }
    }

    private var query: ModelQuery {
        var query = ModelQuery(searchText: searchText, sort: sort)
        switch router.sidebarSelection {
        case .free?: query.freeOnly = true
        case .category(let category)?: query.category = category
        default: break
        }
        return query
    }

    private var visibleModels: [ModelDescriptor] { query.apply(store.models) }

    @ViewBuilder
    private var placeholder: some View {
        if store.isLoading, store.models.isEmpty {
            ProgressView("モデル一覧を取得中…")
        } else if visibleModels.isEmpty, store.loadError == nil {
            if searchText.isEmpty {
                ContentUnavailableView("モデルがありません", systemImage: "tray", description: Text("条件に合うモデルが見つかりませんでした。"))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("並べ替え", selection: $sort) {
                    ForEach(ModelQuery.Sort.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                Label("並べ替え", systemImage: "arrow.up.arrow.down")
            }
            Button {
                showsCatalogStatus = true
            } label: {
                Label("価格情報の取得元", systemImage: "info.circle")
            }
            Button {
                store.reload(settings: settings)
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
        }
    }
}

/// 一覧の上に出すお知らせ（エラー・代替表示・カタログ取得状況）
private struct ModelListBanners: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var showsCatalogStatus: Bool

    var body: some View {
        if let error = store.loadError {
            ErrorCardView(error: error, compact: true, retry: { store.reload(settings: settings) })
                .listRowSeparator(.hidden)
        }
        if store.isUsingCatalogFallback {
            NoticeRow(text: "API からモデル一覧を取得できなかったため、公開カタログのモデルを表示しています。お使いのアカウントでは使えないモデルが含まれる場合があります。", systemImage: "info.circle", color: .orange)
        }
        if store.isRefreshingCatalog {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("最新の価格・パラメータ数を Web から取得中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
        } else if store.catalog.isBundledOnly {
            Button {
                showsCatalogStatus = true
            } label: {
                NoticeRow(text: bundledNotice, systemImage: "clock.arrow.circlepath", color: .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

extension ModelListBanners {
    private var bundledNotice: String {
        let date = BundledCatalog.generatedAt.map { String($0.prefix(10)) } ?? "日付不明"
        return "価格はアプリ同梱のデータです（\(date) 時点）。タップして詳細を確認できます。"
    }
}

struct NoticeRow: View {
    let text: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .listRowSeparator(.hidden)
    }
}
