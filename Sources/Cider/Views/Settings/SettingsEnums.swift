import SwiftUI

enum SettingsCategory: String, CaseIterable {
    case general = "General"
    case notes = "Notes"
    case bookmarks = "Bookmarks"
    case appearance = "Appearance"
    case clipboard = "Clipboard"
    case data = "Data"
    case intelligence = "Intelligence"
    case advanced = "Advanced"
    case about = "About"
    case account = "Account"

    static var primaryCategories: [SettingsCategory] {
        [.general, .notes, .bookmarks, .appearance, .clipboard, .intelligence, .data, .advanced, .about]
    }

    var icon: String {
        switch self {
        case .general:
            "gearshape"
        case .notes:
            "note.text"
        case .bookmarks:
            "square.grid.2x2"
        case .appearance:
            "paintbrush"
        case .clipboard:
            "doc.on.clipboard"
        case .intelligence:
            "sparkles"
        case .data:
            "externaldrive"
        case .advanced:
            "slider.horizontal.3"
        case .about:
            "info.circle"
        case .account:
            "person.crop.circle"
        }
    }

    var subcategories: [SettingsSubcategory] {
        switch self {
        case .general:
            [.startup, .activation, .panelBehavior, .features, .shortcuts]
        case .notes:
            [.notesBehavior, .notesEditor]
        case .bookmarks:
            [.bookmarksBehavior]
        case .appearance:
            [.appearanceText, .appearanceMenuBar, .appearanceSounds]
        case .clipboard:
            [.clipboardBehavior, .clipboardStorage]
        case .intelligence:
            [.intelligenceFeatures]
        case .data:
            [.dataDirectories, .dataTrash, .dataNotifications, .dataImportExport]
        case .advanced:
            [.advancedAccessibility, .advancedReset]
        case .about:
            [.aboutOverview]
        case .account:
            [.accountOverview]
        }
    }
}

enum SettingsSubcategory: Hashable {
    case startup
    case activation
    case panelBehavior
    case features
    case notesBehavior
    case notesEditor
    case bookmarksBehavior
    case appearanceText
    case appearanceMenuBar
    case appearanceSounds
    case clipboardBehavior
    case clipboardStorage
    case dataDirectories
    case dataTrash
    case dataNotifications
    case dataImportExport
    case intelligenceFeatures
    case shortcuts
    case advancedAccessibility
    case advancedReset
    case syncSettings
    case aboutOverview
    case accountOverview

    var title: String {
        switch self {
        case .startup:
            "Startup"
        case .activation:
            "Activation"
        case .panelBehavior:
            "Panel"
        case .features:
            "Features"
        case .shortcuts:
            "Shortcuts"
        case .notesBehavior:
            "Behavior"
        case .notesEditor:
            "Editor"
        case .bookmarksBehavior:
            "Behavior"
        case .appearanceText:
            "Text"
        case .appearanceMenuBar:
            "Menu Bar"
        case .appearanceSounds:
            "Sounds"
        case .clipboardBehavior:
            "Behavior"
        case .clipboardStorage:
            "Storage"
        case .dataDirectories:
            "Directories"
        case .dataTrash:
            "Trash"
        case .dataNotifications:
            "Notifications"
        case .dataImportExport:
            "Import & Export"
        case .intelligenceFeatures:
            "Features"
        case .syncSettings:
            "Cider Web Sync"
        case .advancedAccessibility:
            "Accessibility"
        case .advancedReset:
            "Reset"
        case .aboutOverview:
            "Overview"
        case .accountOverview:
            "Profile"
        }
    }
}
