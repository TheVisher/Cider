import Foundation
import Testing
@testable import Cider

@Suite("Settings navigation")
struct SettingsNavigationTests {
    @Test("Visible categories match the journal-first settings contract")
    func visibleCategories() {
        #expect(SettingsCategory.primaryCategories.map(\.rawValue) == [
            "General",
            "Capture",
            "Reading & Appearance",
            "Intelligence",
            "Data & Privacy",
            "Advanced",
        ])
        #expect(SettingsCategory.primaryCategories.allSatisfy { !$0.subcategories.isEmpty })
    }

    @Test("Existing settings content remains reachable in the new hierarchy")
    func contentReachability() {
        #expect(SettingsCategory.readingAppearance.subcategories.contains(.contentBookmarks))
        #expect(SettingsCategory.readingAppearance.subcategories.contains(.contentNotes))
        #expect(SettingsCategory.readingAppearance.subcategories.contains(.appearanceText))
        #expect(SettingsCategory.capture.subcategories.contains(.captureStorage))
        #expect(SettingsCategory.dataPrivacy.subcategories.contains(.dataTrash))
        #expect(SettingsCategory.advanced.subcategories.contains(.dataDirectories))
        #expect(SettingsCategory.advanced.subcategories.contains(.dataImportExport))
        #expect(SettingsCategory.advanced.subcategories.contains(.accountOverview))
        #expect(SettingsCategory.advanced.subcategories.contains(.syncSettings))
    }

    @Test("Legacy deep links resolve without restoring legacy primary categories")
    func legacyRouteCompatibility() {
        #expect(SettingsNavigationDestination.resolve(category: "content") ==
            .init(category: .readingAppearance, subcategory: .contentBookmarks))
        #expect(SettingsNavigationDestination.resolve(category: "appearance") ==
            .init(category: .readingAppearance, subcategory: .appearanceText))
        #expect(SettingsNavigationDestination.resolve(category: "data", subcategory: "directories") ==
            .init(category: .advanced, subcategory: .dataDirectories))
        #expect(SettingsNavigationDestination.resolve(category: "data", subcategory: "trash") ==
            .init(category: .dataPrivacy, subcategory: .dataTrash))
        #expect(SettingsNavigationDestination.resolve(category: "account") ==
            .init(category: .advanced, subcategory: .accountOverview))
        #expect(SettingsNavigationDestination.resolve(category: "sync") ==
            .init(category: .advanced, subcategory: .syncSettings))
    }

    @Test("Reorganization preserves representative persisted configuration")
    func persistedConfigurationCompatibility() throws {
        var config = CiderConfig.default
        config.activationMode = .singleTap
        config.autoCaptureCopiedURLs = true
        config.journalTimestampFormat = .twentyFourHour
        config.enableSoundEffects = true
        config.enableOCRIndexing = false
        config.trashRetentionDays = 7
        config.directoryOverrides[StorageType.notes.rawValue] = "/tmp/cider-notes"
        config.syncEnabled = true
        config.syncURL = "https://legacy-sync.example.test"

        let decoded = try JSONDecoder().decode(CiderConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.activationMode == .singleTap)
        #expect(decoded.autoCaptureCopiedURLs)
        #expect(decoded.journalTimestampFormat == .twentyFourHour)
        #expect(decoded.enableSoundEffects)
        #expect(decoded.enableOCRIndexing == false)
        #expect(decoded.trashRetentionDays == 7)
        #expect(decoded.directoryOverrides[StorageType.notes.rawValue] == "/tmp/cider-notes")
        #expect(decoded.syncEnabled)
        #expect(decoded.syncURL == "https://legacy-sync.example.test")
    }

    @Test("Cmd-comma and in-app gear use the shared populated Settings surface")
    func sharedSettingsRoute() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let app = try source("Sources/Cider/App/CiderApp.swift", under: root)
        #expect(app.contains("Settings {\n            SettingsView()"))
        #expect(app.contains(".keyboardShortcut(\",\", modifiers: .command)"))
        #expect(app.contains("NotificationCenter.default.post(name: .openCiderSettings, object: nil)"))

        for path in [
            "Sources/Cider/Views/CiderPanelView+SidebarFooter.swift",
            "Sources/Cider/Views/CiderPanelView+ContentArea.swift",
        ] {
            #expect(try source(path, under: root).contains(
                "NotificationCenter.default.post(name: .openCiderSettings, object: nil)"
            ))
        }

        let delegate = try source("Sources/Cider/App/AppDelegate.swift", under: root)
        #expect(delegate.contains("let settingsView = SettingsView()"))
        #expect(delegate.contains("NotificationCenter.default.publisher(for: .openCiderSettings)"))
    }

    @Test("Advanced destination rail is bounded and reveals routed selections")
    func advancedDestinationRailLayout() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let components = try source("Sources/Cider/Views/Settings/SettingsComponents.swift", under: root)
        let afterHeaderMarker = try #require(
            components.split(separator: "// MARK: - Subcategory Header").last
        )
        let header = try #require(afterHeaderMarker.split(separator: "// MARK: - Subcategory Chip").first)

        #expect(header.contains("ScrollViewReader { proxy in"))
        #expect(header.contains("ScrollView(.horizontal, showsIndicators: true)"))
        #expect(header.contains(".id(subcategory)"))
        #expect(header.contains("proxy.scrollTo(selectedSubcategory, anchor: .center)"))
        #expect(header.contains(".onChange(of: selectedSubcategory)"))
        #expect(header.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(header.contains(".clipped()"))
    }

    private func source(_ relativePath: String, under root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
