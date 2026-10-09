import SwiftUI

@main
struct SiliconFlowLabApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = ModelStore()
    @StateObject private var router = AppRouter()
    @StateObject private var chats = ChatSessionRegistry()
    @StateObject private var diagnostics = DiagnosticsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(chats)
                .environmentObject(diagnostics)
        }
    }
}
