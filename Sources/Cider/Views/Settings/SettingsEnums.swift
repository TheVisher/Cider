import SwiftUI

enum SettingsCategory: String, CaseIterable {
    case general = "General"
    case capture = "Capture"
    case readingAppearance = "Reading & Appearance"
    case intelligence = "Intelligence"
    case dataPrivacy = "Data & Privacy"
    case advanced = "Advanced"

    static var primaryCategories: [SettingsCategory] {
        [.general, .capture, .readingAppearance, .intelligence, .dataPrivacy, .advanced]
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "arrow.down.to.line"
        case .readingAppearance: "textformat.size"
        case .intelligence: "sparkles"
        case .dataPrivacy: "hand.raised"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    var subcategories: [SettingsSubcategory] {
        switch self {
        case .general:
            [.startup, .activation, .panelBehavior, .shortcuts, .aboutOverview]
        case .capture:
            [.captureBookmarks, .captureClipboard, .captureStorage]
        case .readingAppearance:
            [.contentBookmarks, .contentNotes, .appearanceText, .appearanceSounds, .appearanceToasts]
        case .intelligence:
            [.intelligenceFeatures]
        case .dataPrivacy:
            [.dataTrash, .dataNotifications]
        case .advanced:
            [.dataDirectories, .dataImportExport, .accountOverview, .syncSettings]
        }
    }
}

struct SettingsNavigationDestination: Equatable {
    let category: SettingsCategory
    let subcategory: SettingsSubcategory

    static func resolve(category rawCategory: String, subcategory rawSubcategory: String? = nil) -> Self? {
        let category = rawCategory.lowercased()
        let subcategory = rawSubcategory?.lowercased()

        switch (category, subcategory) {
        case ("general", _):
            return .init(category: .general, subcategory: .startup)
        case ("capture", _):
            return .init(category: .capture, subcategory: .captureBookmarks)
        case ("content", _):
            return .init(category: .readingAppearance, subcategory: .contentBookmarks)
        case ("appearance", _):
            return .init(category: .readingAppearance, subcategory: .appearanceText)
        case ("reading", _), ("readingappearance", _), ("reading & appearance", _):
            return .init(category: .readingAppearance, subcategory: .contentBookmarks)
        case ("intelligence", _):
            return .init(category: .intelligence, subcategory: .intelligenceFeatures)
        case ("data", "directories"):
            return .init(category: .advanced, subcategory: .dataDirectories)
        case ("data", "importexport"), ("data", "import-export"):
            return .init(category: .advanced, subcategory: .dataImportExport)
        case ("data", "trash"):
            return .init(category: .dataPrivacy, subcategory: .dataTrash)
        case ("data", _), ("dataprivacy", _), ("data & privacy", _):
            return .init(category: .dataPrivacy, subcategory: .dataTrash)
        case ("account", _):
            return .init(category: .advanced, subcategory: .accountOverview)
        case ("sync", _):
            return .init(category: .advanced, subcategory: .syncSettings)
        case ("advanced", _):
            return .init(category: .advanced, subcategory: .dataDirectories)
        default:
            return nil
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
        case .contentNotes: "Journal & Notes"
        case .captureBookmarks: "Bookmarks"
        case .captureClipboard: "Clipboard"
        case .captureStorage: "Storage"
        case .appearanceText: "Text & Menu Bar"
        case .appearanceSounds: "Sounds"
        case .appearanceToasts: "Toasts"
        case .intelligenceFeatures: "Features"
        case .dataDirectories: "Storage & Directories"
        case .dataTrash: "Trash"
        case .dataNotifications: "Notifications"
        case .dataImportExport: "Import, Export & Repair"
        case .aboutOverview: "About"
        case .accountOverview: "Legacy Account"
        case .syncSettings: "Legacy Sync Support"
        }
    }
}
