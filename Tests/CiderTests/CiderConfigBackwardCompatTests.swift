import Foundation
import Testing
@testable import Cider

@Suite("CiderConfig Backward Compatibility Tests")
struct CiderConfigBackwardCompatTests {

    // MARK: - Minimal JSON (simulates old config missing new fields)

    @Test("Decodes empty JSON object with all defaults")
    func emptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.showMenuBarIcon == true)
        #expect(config.textSize == .medium)
        #expect(config.activationMode == .doubleTap)
        #expect(config.enableNotesHotkey == true)
        #expect(config.enableBookmarksHotkey == true)
        #expect(config.autoCaptureCopiedURLs == false)
        #expect(config.vaultDirectory == "~/CiderVault")
        #expect(config.directoryOverrides.isEmpty)
        #expect(config.rememberPanelPosition == true)
        #expect(config.bookmarksDefaultViewMode == .masonry)
        #expect(config.detailViewMode == .slideOut)
        #expect(config.trashRetentionDays == 30)
        #expect(config.enableSpotlightIndexing == false)
        #expect(config.enableSoundEffects == false)
        #expect(config.enableAutoTagging == true)
        #expect(config.enableClipboardHistory == true)
        #expect(config.syncEnabled == false)
        #expect(config.syncURL == "")
        #expect(config.hasCompletedOnboarding == false)
        #expect(config.didMigrateBookmarkFiles == false)
        #expect(config.lastReconciliationAt == 0)
    }

    @Test("Preserves explicitly set values through encode/decode round-trip")
    func roundTrip() throws {
        var config = CiderConfig.default
        config.showMenuBarIcon = false
        config.textSize = .large
        config.activationMode = .singleTap
        config.trashRetentionDays = 7
        config.enableSoundEffects = true
        config.syncEnabled = true
        config.syncURL = "https://test.convex.site"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(decoded.showMenuBarIcon == false)
        #expect(decoded.textSize == .large)
        #expect(decoded.activationMode == .singleTap)
        #expect(decoded.trashRetentionDays == 7)
        #expect(decoded.enableSoundEffects == true)
        #expect(decoded.syncEnabled == true)
        #expect(decoded.syncURL == "https://test.convex.site")
    }

    @Test("Old config without clipboard fields gets correct defaults")
    func missingClipboardFields() throws {
        // Simulate a config from before clipboard was added
        let json = """
        {"showMenuBarIcon": true, "textSize": "medium"}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.enableClipboardHistory == true)
        #expect(config.enableClipboardHotkey == true)
        #expect(config.clipboardRetentionDays == 30)
        #expect(config.clipboardImageRetentionDays == 7)
        #expect(config.clipboardMaxImageStorageMB == 500)
        #expect(config.clipboardPanelPosition == .followMouse)
    }

    @Test("Old config without sync fields gets correct defaults")
    func missingSyncFields() throws {
        let json = """
        {"showMenuBarIcon": false}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.syncEnabled == false)
        #expect(config.syncURL == "")
        #expect(config.syncToken == "")
        #expect(config.lastSyncTimestamp == 0)
        #expect(config.lastSuccessfulPushAt == 0)
        #expect(config.lastReconciliationAt == 0)
    }

    @Test("Old config without AI fields gets correct defaults")
    func missingAIFields() throws {
        let json = """
        {"showMenuBarIcon": true}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.enableAutoTagging == true)
        #expect(config.enableEmbeddings == true)
        #expect(config.enablePageSummaries == true)
        #expect(config.enableOCRIndexing == false)
        #expect(config.enableColorExtraction == true)
        // TODO: Restore when aiChatDocked/aiChatVisible are added to CiderConfig
        // #expect(config.aiChatDocked == false)
        // #expect(config.aiChatVisible == false)
    }

    @Test("Old config without migration flags gets correct defaults")
    func missingMigrationFlags() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.didMigrateBookmarkFiles == false)
        #expect(config.didMigrateVaultToCiderDir == false)
        #expect(config.didMigrateContentToInbox == false)
        #expect(config.didMigrateContactsToPerFile == false)
        #expect(config.didMigrateTodosToPerFile == false)
        #expect(config.didMigrateDateCardsToPerFile == false)
    }

    @Test("Old config without screen capture fields gets correct defaults")
    func missingScreenCaptureFields() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.screenCaptureToastTimeout == 8)
        #expect(config.screenCaptureDefaultAction == "note")
    }

    @Test("Old config without date card notification fields gets correct defaults")
    func missingDateCardNotificationFields() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.dateCardSurfacingDays == 7)
        #expect(config.enableDateCardNotifications == false)
        #expect(config.dateCardDefaultNotificationMinutes == 30)
    }

    @Test("Optional fields survive round-trip as nil")
    func optionalFieldsNil() throws {
        var config = CiderConfig.default
        config.bookmarksCardSizeScale = nil
        config.notesCardSizeScale = nil
        config.bookmarkDetailViewMode = nil
        config.noteDetailViewMode = nil
        config.detailSlideOutWidth = nil
        config.homeCardSizeScale = nil

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(decoded.bookmarksCardSizeScale == nil)
        #expect(decoded.notesCardSizeScale == nil)
        #expect(decoded.bookmarkDetailViewMode == nil)
        #expect(decoded.noteDetailViewMode == nil)
        #expect(decoded.detailSlideOutWidth == nil)
        #expect(decoded.homeCardSizeScale == nil)
    }

    @Test("Optional fields survive round-trip with values")
    func optionalFieldsSet() throws {
        var config = CiderConfig.default
        config.bookmarksCardSizeScale = 1.5
        config.notesCardSizeScale = 2.0
        config.bookmarkDetailViewMode = .fullPanel
        config.noteDetailViewMode = .slideOut
        config.detailSlideOutWidth = 450
        config.homeCardSizeScale = 0.8

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(decoded.bookmarksCardSizeScale == 1.5)
        #expect(decoded.notesCardSizeScale == 2.0)
        #expect(decoded.bookmarkDetailViewMode == .fullPanel)
        #expect(decoded.noteDetailViewMode == .slideOut)
        #expect(decoded.detailSlideOutWidth == 450)
        #expect(decoded.homeCardSizeScale == 0.8)
    }

    // MARK: - Legacy Migration

    @Test("Legacy detailModalMode 'expand' maps to fullPanel")
    func legacyDetailModalModeExpand() throws {
        let json = """
        {"detailModalMode": "expand"}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)
        #expect(config.detailViewMode == .fullPanel)
    }

    @Test("Legacy detailModalMode non-expand maps to slideOut")
    func legacyDetailModalModeOther() throws {
        let json = """
        {"detailModalMode": "modal"}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)
        #expect(config.detailViewMode == .slideOut)
    }

    @Test("Missing detailViewMode without legacy key defaults to slideOut")
    func missingDetailViewMode() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)
        #expect(config.detailViewMode == .slideOut)
    }

    // MARK: - Default static matches decoder defaults

    @Test("Default static property matches empty-JSON decode for key fields")
    func defaultMatchesEmptyDecode() throws {
        let defaultConfig = CiderConfig.default
        let json = "{}"
        let decoded = try JSONDecoder().decode(CiderConfig.self, from: json.data(using: .utf8)!)

        #expect(defaultConfig.showMenuBarIcon == decoded.showMenuBarIcon)
        #expect(defaultConfig.textSize == decoded.textSize)
        #expect(defaultConfig.activationMode == decoded.activationMode)
        #expect(defaultConfig.vaultDirectory == decoded.vaultDirectory)
        #expect(defaultConfig.trashRetentionDays == decoded.trashRetentionDays)
        #expect(defaultConfig.enableAutoTagging == decoded.enableAutoTagging)
        #expect(defaultConfig.enableClipboardHistory == decoded.enableClipboardHistory)
        #expect(defaultConfig.syncEnabled == decoded.syncEnabled)
        #expect(defaultConfig.hasCompletedOnboarding == decoded.hasCompletedOnboarding)
    }
}
