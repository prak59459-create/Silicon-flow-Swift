import SwiftUI
import SiliconFlowKit

/// 価格・パラメータ数をどこから取得したか（情報源ごとの成否）
struct CatalogStatusView: View {
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.catalog.statuses) { status in
                        SourceStatusRow(status: status)
                    }
                    if store.catalog.statuses.isEmpty {
                        Text("まだ取得していません")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("情報源")
                } footer: {
                    Text(updatedText)
                }
                Section {
                    Button {
                        Task { await store.refreshCatalog(region: settings.region, options: settings.catalogOptions) }
                    } label: {
                        HStack {
                            Label("今すぐ Web から取得", systemImage: "arrow.down.circle")
                            if store.isRefreshingCatalog {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isRefreshingCatalog)
                }
                Section("それぞれの情報源について") {
                    ExplanationRow(title: "SiliconFlow公式サイト", text: "siliconflow.cn の料金ページから人民元の価格・パラメータ数・コンテキスト長を直接読み取ります（中国版のみ）。")
                    ExplanationRow(title: "GitHub カタログ", text: "GitHub Actions が毎日、公式サイト・models.dev・Hugging Face から集めて更新しているデータです。")
                    ExplanationRow(title: "models.dev", text: "オープンなモデル情報データベース。国際版の米ドル価格や仕様に使います。")
                    ExplanationRow(title: "Hugging Face", text: "モデルの詳細画面を開いたとき、実際のパラメータ数を取得します。")
                    ExplanationRow(title: "同梱データ", text: "ネットに繋がらないときでも表示できるよう、アプリに入れてある最終手段のデータです。")
                }
            }
            .navigationTitle("価格情報の取得元")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var updatedText: String {
        guard let date = store.catalog.updatedAt else { return "Web からはまだ取得できていません（同梱データを表示中）。" }
        return "最終更新: \(DisplayFormat.dateTime(date))"
    }
}

private struct SourceStatusRow: View {
    let status: CatalogSourceStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.succeeded ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                    .font(.subheadline.weight(.semibold))
                Text(status.succeeded ? "\(status.entryCount) モデル" : "取得できませんでした")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = status.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ExplanationRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
