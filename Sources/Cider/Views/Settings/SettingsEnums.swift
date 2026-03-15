import SwiftUI

enum SettingsCategory: String, CaseIterable {
    case general = "General"
    case content = "Content"
    case capture = "Capture"
    case appearance = "Appearance"
    case intelligence = "Intelligence"
    case data = "Data"
    case about = "About"
    case account = "Account"

    static var primaryCategories: [SettingsCategory] {
        [.general, .content, .capture, .appearance, .intelligence, .data, .about]
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .content: "square.stack"
        case .capture: "arrow.down.to.line"
        case .appearance: "paintbrush"
        case .intelligence: "sparkles"
        case .data: "externaldrive"
        case .about: "info.circle"
        case .account: "person.crop.circle"
        }
    }

    var subcategories: [SettingsSubcategory] {
        switch self {
        case .general:
            [.startup, .activation, .panelBehavior, .shortcuts]
        case .content:
            [.contentBookmarks, .contentNotes]
        case .capture:
            [.captureBookmarks, .captureClipboard, .captureStorage]
        case .appearance:
            [.appearanceText, .appearanceSounds, .appearanceToasts]
        case .intelligence:
            [.intelligenceFeatures]
        case .data:
            [.dataDirectories, .dataTrash, .dataNotifications, .dataImportExport]
        case .about:
            [.aboutOverview]
        case .account:
            [.accountOverview]
        }
    }
}

enum SettingsSubcategory: Hashable {
    // General
    case startup
    case activation
    case panelBehavior
    case shortcuts

    // Content
    case contentBookmarks
    case contentNotes

    // Capture
    case captureBookmarks
    case captureClipboard
    case captureStorage

    // Appearance
    case appearanceText
    case appearanceSounds
    case appearanceToasts

    // Intelligence
    case intelligenceFeatures

    // Data
    case dataDirectories
    case dataTrash
    case dataNotifications
    case dataImportExport

    // About
    case aboutOverview

    // Account
    case accountOverview

    // Legacy (kept for compile compat, unused in sidebar)
    case syncSettings

    var title: String {
        switch self {
        case .startup: "Startup"
        case .activation: "Activation"
        case .panelBehavior: "Panel"
        case .shortcuts: "Shortcuts"
        case .contentBookmarks: "Bookmarks"
        case .contentNotes: "Notes"
        case .captureBookmarks: "Bookmarks"
        case .captureClipboard: "Clipboard"
        case .captureStorage: "Storage"
        case .appearanceText: "Text & Menu Bar"
        case .appearanceSounds: "Sounds"
        case .appearanceToasts: "Toasts"
        case .intelligenceFeatures: "Features"
        case .dataDirectories: "Directories"
        case .dataTrash: "Trash"
        case .dataNotifications: "Notifications"
        case .dataImportExport: "Import & Export"
        case .aboutOverview: "Overview"
        case .accountOverview: "Profile"
        case .syncSettings: "Sync"
        }
    }
}
