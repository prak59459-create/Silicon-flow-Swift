import SwiftUI
import SiliconFlowKit

/// API キーが無ければ初期設定、あればメイン画面を表示します。
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chats: ChatSessionRegistry
    @EnvironmentObject private var diagnostics: DiagnosticsStore

    var body: some View {
        content
            .sheet(item: $router.sheet) { sheet in
                sheetContent(sheet)
                    .environmentObject(settings)
                    .environmentObject(store)
                    .environmentObject(router)
                    .environmentObject(chats)
                    .environmentObject(diagnostics)
            }
            .onChange(of: settings.connectionRevision) {
                router.selectedModelID = nil
                if settings.hasAnyKey { store.reload(settings: settings) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if settings.hasAnyKey {
            MainSplitView()
                .task { store.reload(settings: settings) }
        } else {
            OnboardingView()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppRouter.Sheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .diagnostics:
            DiagnosticsView()
        case .chatParameters:
            ChatParametersView()
        }
    }
}
