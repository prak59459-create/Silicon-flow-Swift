import SwiftUI
import SiliconFlowKit

/// 価格・パラメータ数の取得元の設定
struct CatalogSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @State private var isClearing = false

    var body: some View {
        Section {
            Toggle("公式サイトから直接取得（中国版）", isOn: $settings.catalogOptions.useOfficialSite)
            Toggle("GitHub のカタログ（毎日自動更新）", isOn: $settings.catalogOptions.useRemoteCatalog)
            Toggle("models.dev（予備）", isOn: $settings.catalogOptions.useModelsDev)
            Toggle("Hugging Face でパラメータ数を確認", isOn: $settings.useHuggingFace)
            Toggle("円換算を表示", isOn: $settings.showYen)
            Button {
                Task { await store.refreshCatalog(region: settings.region, options: settings.catalogOptions) }
            } label: {
                HStack {
                    Label("価格情報を今すぐ更新", systemImage: "arrow.down.circle")
                    if store.isRefreshingCatalog {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(store.isRefreshingCatalog)
            Button(role: .destructive) {
                isClearing = true
                Task {
                    await store.clearCaches()
                    isClearing = false
                }
            } label: {
                Label("保存した価格・パラメータ情報を削除", systemImage: "trash")
            }
            .disabled(isClearing)
        } header: {
            Text("価格・パラメータ数の取得元")
        } footer: {
            Text("どれも使えないときはアプリ同梱のデータを表示します。円換算は ExchangeRate-API / 欧州中央銀行のレートを使った目安です。")
        }
    }
}

/// アプリの情報
struct AboutSection: View {
    @EnvironmentObject private var chats: ChatSessionRegistry
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Section {
            LabeledContent("バージョン", value: version)
            LabeledContent("同梱カタログ", value: BundledCatalog.generatedAt.map { String($0.prefix(10)) } ?? "なし")
            Link(destination: URL(string: "https://github.com/prak59459-create/Silicon-flow-Swift")!) {
                Label("ソースコード（GitHub）", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: settings.region.docsURL) {
                Label("SiliconFlow のドキュメント", systemImage: "book")
            }
            Link(destination: settings.region.errorDocsURL) {
                Label("エラーコードの説明", systemImage: "exclamationmark.bubble")
            }
            Button(role: .destructive) {
                chats.clearAll()
            } label: {
                Label("すべての会話を消去", systemImage: "trash")
            }
        } header: {
            Text("このアプリについて")
        } footer: {
            Text("価格は SiliconFlow 公式サイト・models.dev、パラメータ数は公式サイト・Hugging Face の公開情報をもとに表示しています。実際の請求額は SiliconFlow のコンソールで確認してください。")
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
