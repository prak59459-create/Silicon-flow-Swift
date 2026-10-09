import Foundation
import SiliconFlowKit

/// サイドバーの項目
enum SidebarItem: Hashable {
    case all
    case free
    case category(ModelCategory)

    var title: String {
        switch self {
        case .all: return "すべてのモデル"
        case .free: return "無料のモデル"
        case .category(let category): return category.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .free: return "gift"
        case .category(let category): return category.systemImage
        }
    }
}

/// 画面遷移の状態
@MainActor
final class AppRouter: ObservableObject {
    enum Sheet: String, Identifiable {
        case settings
        case diagnostics
        case chatParameters

        var id: String { rawValue }
    }

    @Published var sheet: Sheet?
    @Published var sidebarSelection: SidebarItem? = .all
    @Published var selectedModelID: String?

    func show(_ sheet: Sheet) {
        self.sheet = sheet
    }
}
