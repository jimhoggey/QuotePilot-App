import Foundation

/// The six places in the window's tree, in order.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard, quotes, invoices, clients, activity, brand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .quotes: return "Quotes"
        case .invoices: return "Invoices"
        case .clients: return "Clients"
        case .activity: return "Activity"
        case .brand: return "Brand"
        }
    }

    public var icon: PixelIcon {
        switch self {
        case .dashboard: return .dashboard
        case .quotes: return .quote
        case .invoices: return .invoice
        case .clients: return .client
        case .activity: return .activity
        case .brand: return .brand
        }
    }

    /// ⌘1 to ⌘6, in tree order.
    public var shortcut: Character {
        Character(String(AppSection.allCases.firstIndex(of: self)! + 1))
    }
}
