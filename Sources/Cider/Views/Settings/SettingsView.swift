import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory = .general
    @State private var selectedSubcategory: SettingsSubcategory = .startup
    @State private var importResult: String?
    @State private var exportResult: String?
    @State private var automaticallyChecksForUpdates = SparkleUpdaterService.shared.automaticallyChecksForUpdates

    var body: some View {
        ZStack {
            SettingsBackgroundView(cornerRadius: SettingsDesign.cornerRadius)

            HStack(spacing: 0) {
                SettingsPrimarySidebar(
                    selectedCategory: $selectedCategory,
                    onSelectAccount: { selectedCategory = .account },
                    onClose: { NotificationCenter.default.post(name: .dismissSettings, object: nil) }
                )
                .frame(width: SettingsDesign.primarySidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .opacity(CiderColors.dividerPrimaryOpacity)

                VStack(spacing: 0) {
                    SettingsSubcategoryHeader(
                        category: selectedCategory,
                        selectedSubcategory: $selectedSubcategory
                    )
                    .padding(.horizontal, Spacing.md)
                    .frame(height: SettingsDesign.headerHeight)

                    Divider()
                        .opacity(CiderColors.dividerSecondaryOpacity)

                    ScrollView {
                        selectedSubcategoryContent
                            .padding(Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.cornerRadius, style: .continuous))
        }
        .frame(width: SettingsDesign.width, height: SettingsDesign.height)
        .environmentObject(viewModel)
        .onAppear {
            syncSelectedSubcategory(reset: true)
        }
        .onChange(of: selectedCategory) { _, _ in
            syncSelectedSubcategory(reset: true)
        }
        .onChange(of: automaticallyChecksForUpdates) { _, newValue in
            SparkleUpdaterService.shared.automaticallyChecksForUpdates = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsNavigate)) { notification in
            guard let category = notification.userInfo?["category"] as? String else { return }
            switch category {
            case "data": selectedCategory = .data
            case "general": selectedCategory = .general
            case "appearance": selectedCategory = .appearance
            case "clipboard": selectedCategory = .clipboard
            default: break
            }
        }
    }

    @ViewBuilder
    private var selectedSubcategoryContent: some View {
        switch selectedSubcategory {
        case .startup:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Startup") {
                    SettingsToggleRow(
                        title: "Launch Cider at login",
                        subtitle: "Automatically start Cider when you log in",
                        isOn: $viewModel.launchAtLogin
                    )
                }
                SettingsSection(title: "Updates") {
                    SettingsToggleRow(
                        title: "Check for updates automatically",
                        subtitle: "Periodically check for new versions of Cider",
                        isOn: $automaticallyChecksForUpdates
                    )

                    HStack {
                        Button("Check for Updates Now") {
                            SparkleUpdaterService.shared.checkForUpdates()
                        }
                        .controlSize(.small)

                        if let lastCheck = SparkleUpdaterService.shared.lastUpdateCheckDate {
                            Text("Last checked: \(lastCheck, style: .relative) ago")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .activation:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Activation") {
                    SettingsPickerRow(
                        title: "Option key activation",
                        subtitle: "How to open Cider",
                        selection: $viewModel.activationMode,
                        options: ActivationMode.allCases,
                        label: { $0.displayName }
                    )

                    if viewModel.activationMode == .doubleTap {
                        SettingsSliderRow(
                            title: "Double-tap speed",
                            value: $viewModel.hotkeyDoubleTapInterval,
                            range: 0.2...0.5,
                            labels: ("Fast", "Slow")
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .panelBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Panel") {
                    SettingsToggleRow(
                        title: "Remember panel position",
                        subtitle: "Reopen the panel at its last position and size",
                        isOn: $viewModel.rememberPanelPosition
                    )

                    SettingsPickerRow(
                        title: "Detail view mode",
                        subtitle: "How bookmark details appear",
                        selection: $viewModel.detailViewMode,
                        options: DetailViewMode.allCases,
                        label: { $0.displayName }
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .notesBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Notes Behavior") {
                    SettingsToggleRow(
                        title: "Option+N to create note",
                        subtitle: "Open the panel and start a new note",
                        isOn: $viewModel.enableNotesHotkey
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .notesEditor:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Notes Editor") {
                    SettingsPickerRow(
                        title: "Default note text size",
                        subtitle: "Sets the base display size for note content",
                        selection: $viewModel.notesEditorTextSize,
                        options: NotesEditorTextSize.allCases,
                        label: { $0.displayName }
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .features:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Features") {
                    SettingsToggleRow(
                        title: "Linked Sources",
                        subtitle: "Watch external folders and surface their .md files in Cider",
                        isOn: $viewModel.enableLinkedSources
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .shortcuts:
            KeyboardShortcutsReferenceView()

        case .bookmarksBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Bookmarks") {
                    SettingsToggleRow(
                        title: "Option+B to capture bookmark",
                        subtitle: "Capture the current browser tab as a bookmark",
                        isOn: $viewModel.enableBookmarksHotkey
                    )

                    SettingsToggleRow(
                        title: "Option+Shift+B to capture active tab",
                        subtitle: "Save the current browser tab instantly",
                        isOn: $viewModel.enableBookmarksCaptureHotkey
                    )

                    SettingsToggleRow(
                        title: "Auto-save copied URLs",
                        subtitle: "Whenever you copy a web link, save it as a bookmark",
                        isOn: $viewModel.autoCaptureCopiedURLs
                    )

                    SettingsToggleRow(
                        title: "Review copied URLs before save",
                        subtitle: "Show Save/Discard toast; auto-discard if ignored",
                        isOn: $viewModel.confirmCopiedURLBeforeSave
                    )
                    .disabled(!viewModel.autoCaptureCopiedURLs)
                    .opacity(viewModel.autoCaptureCopiedURLs ? 1.0 : CiderColors.disabledOpacity)

                    SettingsToggleRow(
                        title: "Detect copied images",
                        subtitle: "When you copy an image, offer to save it as a bookmark",
                        isOn: $viewModel.autoCaptureCopiedImages
                    )

                    SettingsPickerRow(
                        title: "Default view mode",
                        subtitle: "Choose how bookmarks are shown by default",
                        selection: $viewModel.bookmarksDefaultViewMode,
                        options: BookmarkDisplayMode.allCases,
                        label: { $0.displayName }
                    )

                    SettingsPickerRow(
                        title: "Default card size",
                        subtitle: "Set bookmark card scale for grid and masonry",
                        selection: $viewModel.bookmarksCardSize,
                        options: BookmarkCardSize.allCases,
                        label: { $0.displayName }
                    )

                    SettingsToggleRow(
                        title: "Show drag mode hints",
                        subtitle: "Show overlay hints when dragging bookmarks with both image and URL",
                        isOn: $viewModel.showDragModeHints
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .appearanceText:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Text Size") {
                    HStack(spacing: Spacing.md) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            SettingsSizeOptionButton(
                                title: size.displayName,
                                preview: "Aa",
                                previewSize: 14 * size.scale,
                                isSelected: viewModel.textSize == size,
                                action: { viewModel.textSize = size }
                            )
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .appearanceMenuBar:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Menu Bar") {
                    SettingsToggleRow(
                        title: "Show in menu bar",
                        subtitle: "Display Cider icon in the system menu bar",
                        isOn: $viewModel.showMenuBarIcon
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .appearanceSounds:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Sounds") {
                    SettingsToggleRow(
                        title: "Sound effects",
                        subtitle: "Play sounds for saves, captures, and deletes",
                        isOn: $viewModel.enableSoundEffects
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .clipboardBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Clipboard Monitor") {
                    SettingsToggleRow(
                        title: "Monitor clipboard history",
                        subtitle: "Record copied items for the clipboard viewer",
                        isOn: $viewModel.enableClipboardHistory
                    )
                    SettingsToggleRow(
                        title: "Clipboard viewer hotkey (\u{2325}V)",
                        subtitle: "Toggle the clipboard viewer with Option+V",
                        isOn: $viewModel.enableClipboardHotkey
                    )
                }
                SettingsSection(title: "Standalone Panel") {
                    SettingsPickerRow(
                        title: "Panel position",
                        subtitle: "Where the clipboard panel appears when opened via hotkey",
                        selection: $viewModel.clipboardPanelPosition,
                        options: ClipboardPanelPosition.allCases,
                        label: { $0.displayName }
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .clipboardStorage:
            ClipboardStorageSettingsView()
                .environmentObject(viewModel)

        case .advancedAccessibility:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Accessibility") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Button(action: openAccessibilityPreferences) {
                            Label("Open Accessibility Settings", systemImage: "hand.raised")
                        }
                        .buttonStyle(CiderAccentButtonStyle())

                        Text("Cider requires accessibility permissions to manage windows.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .advancedReset:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Reset") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Button(action: {}) {
                            Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(CiderDestructiveButtonStyle())

                        Text("This will reset all settings to their default values.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .dataDirectories:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Vault Location") {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Cider Vault")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Text(viewModel.vaultDirectory)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)

                            Text("Default location for all Cider data")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseVaultDirectory()
                        }
                        .controlSize(.small)
                    }
                }

                SettingsSection(title: "Directory Overrides") {
                    Text("Point individual data types to custom locations (e.g., Notes to an Obsidian vault).")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)

                    ForEach(overrideableTypes, id: \.self) { type in
                        if type != overrideableTypes.first {
                            Divider()
                                .opacity(CiderColors.dividerSecondaryOpacity)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(type.rawValue)
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.primary)

                                Text(viewModel.displayPath(for: type))
                                    .font(CiderFont.caption)
                                    .foregroundColor(
                                        viewModel.hasOverride(for: type)
                                            ? CiderColors.secondary
                                            : CiderColors.quaternary
                                    )
                                    .lineLimit(1)
                            }

                            Spacer()

                            if viewModel.hasOverride(for: type) {
                                Button("Reset") {
                                    viewModel.clearDirectoryOverride(for: type)
                                }
                                .controlSize(.small)
                            }

                            Button("Override...") {
                                chooseDirectoryOverride(for: type)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                SettingsSection(title: "Indexing") {
                    SettingsToggleRow(
                        title: "Spotlight indexing",
                        subtitle: "Index Cider items for Spotlight, Raycast, and Alfred (requires .app bundle)",
                        isOn: $viewModel.enableSpotlightIndexing
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .dataTrash:
            StorageSettingsView()

        case .dataNotifications:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Toast Notifications") {
                    SettingsPickerRow(
                        title: "Capture toast position",
                        subtitle: "Where the bookmark capture confirmation appears",
                        selection: $viewModel.captureToastPosition,
                        options: ToastPosition.allCases,
                        label: { $0.displayName }
                    )

                    SettingsPickerRow(
                        title: "Undo toast position",
                        subtitle: "Where the undo action toast appears",
                        selection: $viewModel.undoToastPosition,
                        options: ToastPosition.allCases,
                        label: { $0.displayName }
                    )
                }

                SettingsSection(title: "Date Card Notifications") {
                    SettingsToggleRow(
                        title: "Enable notifications",
                        subtitle: "Send system notifications for approaching date cards",
                        isOn: $viewModel.enableDateCardNotifications
                    )

                    if viewModel.enableDateCardNotifications {
                        SettingsPickerRow(
                            title: "Default notification time",
                            subtitle: "When to notify before events without a custom reminder",
                            selection: $viewModel.dateCardDefaultNotificationMinutes,
                            options: [5, 15, 30, 60, 120, 1440],
                            label: { minutes in
                                switch minutes {
                                case 5: return "5 minutes before"
                                case 15: return "15 minutes before"
                                case 30: return "30 minutes before"
                                case 60: return "1 hour before"
                                case 120: return "2 hours before"
                                case 1440: return "1 day before"
                                default: return "\(minutes) minutes before"
                                }
                            }
                        )

                        Text("Grant notification permission in System Settings \u{2192} Notifications if notifications don't appear.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .dataImportExport:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Import Bookmarks") {
                    Text("Import bookmarks from Chrome, Firefox, Safari, or any browser that exports Netscape HTML format.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    HStack(spacing: Spacing.sm) {
                        Button(action: importBookmarks) {
                            Label("Import from File\u{2026}", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(CiderAccentButtonStyle())

                        if let importResult {
                            Text(importResult)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }
                    }

                    Text("To export from your browser: Chrome \u{2192} Bookmarks Manager \u{2192} \u{22EE} \u{2192} Export bookmarks. Firefox \u{2192} Bookmarks \u{2192} Manage \u{2192} Import and Backup \u{2192} Export to HTML. Safari \u{2192} File \u{2192} Export Bookmarks.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }

                SettingsSection(title: "Export Bookmarks") {
                    Text("Export all bookmarks as Netscape HTML. This file can be imported into any browser or bookmark manager.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    HStack(spacing: Spacing.sm) {
                        Button(action: exportBookmarks) {
                            Label("Export to File\u{2026}", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(CiderSecondaryButtonStyle())

                        if let exportResult {
                            Text(exportResult)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        } else {
                            Text("\(BookmarksStorage.shared.bookmarks.count) bookmarks")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .intelligenceFeatures:
            IntelligenceSettingsView()
                .frame(maxWidth: .infinity, alignment: .leading)

        case .aboutOverview:
            AboutSettingsView()
                .frame(maxWidth: .infinity, alignment: .leading)

        case .accountOverview:
            SettingsAccountOverviewView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func syncSelectedSubcategory(reset: Bool) {
        let options = selectedCategory.subcategories
        guard let first = options.first else { return }

        if reset || !options.contains(selectedSubcategory) {
            selectedSubcategory = first
        }
    }

    private var overrideableTypes: [StorageType] {
        [.bookmarks, .notes, .contacts, .dateCards, .stacks, .labels, .savedViews, .sources]
    }

    private func chooseVaultDirectory() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Select a root directory for the Cider Vault"

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let oldVaultURL = StoragePaths.vaultDirectoryURL()
            let newVaultURL = url
            guard oldVaultURL.path != newVaultURL.path else { return }

            let hasData = Self.vaultHasData(at: oldVaultURL)
            if hasData {
                let result = Self.offerMigration(
                    message: "Move your Cider data to the new location?",
                    detail: "Your bookmarks, notes, and other data can be moved from:\n\(oldVaultURL.path)\n\nTo:\n\(newVaultURL.path)",
                    moveAction: {
                        Self.migrateVault(from: oldVaultURL, to: newVaultURL)
                    }
                )
                if result == .cancelled { return }
            }

            let path = newVaultURL.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.vaultDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.vaultDirectory = path
            }
        }
    }

    private func chooseDirectoryOverride(for type: StorageType) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Select a directory for \(type.rawValue)"

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let oldDirURL = StoragePaths.directoryURL(for: type)
            let newDirURL = url
            guard oldDirURL.path != newDirURL.path else { return }

            let hasData = Self.directoryHasData(at: oldDirURL)
            if hasData {
                let result = Self.offerMigration(
                    message: "Move your \(type.rawValue) data to the new location?",
                    detail: "Your \(type.rawValue.lowercased()) data can be moved from:\n\(oldDirURL.path)\n\nTo:\n\(newDirURL.path)",
                    moveAction: {
                        Self.migrateDirectoryContents(from: oldDirURL, to: newDirURL)
                    }
                )
                if result == .cancelled { return }
            }

            let path = newDirURL.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.setDirectoryOverride(for: type, path: "~" + path.dropFirst(home.count))
            } else {
                viewModel.setDirectoryOverride(for: type, path: path)
            }
        }
    }

    // MARK: - Vault Migration

    private enum MigrationResult {
        case moved, skipped, cancelled
    }

    /// Shows an alert offering to move data.
    private static func offerMigration(
        message: String,
        detail: String,
        moveAction: () -> Bool
    ) -> MigrationResult {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move Data")
        alert.addButton(withTitle: "Don't Move")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            _ = moveAction()
            return .moved
        case .alertSecondButtonReturn:
            return .skipped
        default:
            return .cancelled
        }
    }

    /// Checks if a vault root directory has any meaningful data.
    private static func vaultHasData(at vaultURL: URL) -> Bool {
        let fm = FileManager.default
        for type in StorageType.allCases {
            let typeDir = vaultURL.appendingPathComponent(type.rawValue)
            if let contents = try? fm.contentsOfDirectory(atPath: typeDir.path),
               !contents.filter({ !$0.hasPrefix(".") || $0 == ".trash" || $0 == ".attachments" }).isEmpty {
                return true
            }
        }
        return false
    }

    /// Checks if a single directory has any data files.
    private static func directoryHasData(at dirURL: URL) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return false }
        return !contents.filter({ !$0.hasPrefix(".") || $0 == ".trash" || $0 == ".attachments" }).isEmpty
    }

    /// Moves all vault type subdirectories from old location to new.
    @discardableResult
    private static func migrateVault(from oldVault: URL, to newVault: URL) -> Bool {
        let fm = FileManager.default
        var success = true

        for type in StorageType.allCases {
            let oldDir = oldVault.appendingPathComponent(type.rawValue)
            let newDir = newVault.appendingPathComponent(type.rawValue)

            guard fm.fileExists(atPath: oldDir.path) else { continue }
            if !migrateDirectoryContents(from: oldDir, to: newDir) {
                success = false
            }
        }

        // Also migrate .ai directory (embeddings)
        let oldAI = oldVault.appendingPathComponent(".ai")
        let newAI = newVault.appendingPathComponent(".ai")
        if fm.fileExists(atPath: oldAI.path) {
            if !migrateDirectoryContents(from: oldAI, to: newAI) {
                success = false
            }
        }

        return success
    }

    /// Moves the contents of one directory into another, preserving existing files at destination.
    @discardableResult
    private static func migrateDirectoryContents(from source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        StoragePaths.ensureDirectory(destination)

        guard let items = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return true // Empty source = nothing to do
        }

        var success = true
        for item in items {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: destItem.path) {
                // Skip existing files at destination to avoid data loss
                continue
            }
            do {
                try fm.moveItem(at: item, to: destItem)
            } catch {
                success = false
            }
        }
        return success
    }

    private func importBookmarks() {
        // Defer to next run loop tick — NSSavePanel/NSOpenPanel init deadlocks
        // when called synchronously inside a SwiftUI button gesture dispatch.
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.canCreateDirectories = false
            panel.allowedContentTypes = [.html]
            panel.prompt = "Import"
            panel.message = "Select a bookmark HTML file to import"

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                let count = BookmarksStorage.shared.importNetscapeHTML(from: url)
                importResult = "Imported \(count) bookmarks"
            }
        }
    }

    private func exportBookmarks() {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = "CiderBookmarks.html"
            panel.prompt = "Export"
            panel.message = "Choose where to save your bookmarks"

            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try BookmarksStorage.shared.exportNetscapeHTML(to: url)
                    exportResult = "Exported successfully"
                } catch {
                    exportResult = "Export failed"
                }
            }
        }
    }

    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

}

private enum SettingsCategory: String, CaseIterable {
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

private enum SettingsSubcategory: Hashable {
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

enum SettingsDesign {
    static let width: CGFloat = 750
    static let height: CGFloat = 580
    static let cornerRadius: CGFloat = Radius.lg
    static let shadowPadding: CGFloat = 16
    static let headerHeight: CGFloat = 48
    static let primarySidebarWidth: CGFloat = 190
    static let displayPickerMaxWidth: CGFloat = 250
}

private struct SettingsPrimarySidebar: View {
    @Binding var selectedCategory: SettingsCategory
    let onSelectAccount: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                SidebarTrafficLightButton(color: .systemRed, help: "Close Settings", action: onClose)
                SidebarTrafficLightButton(color: .systemYellow, help: "Floating panel", action: {})
                SidebarTrafficLightButton(color: .systemGreen, help: "Floating panel", action: {})
            }

            Button(action: onSelectAccount) {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(CiderColors.accentMedium)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(CiderFont.navTitle)
                                .foregroundColor(CiderColors.controlAccent)
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Local Account")
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)

                        Text("Profile settings")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(selectedCategory == .account ? CiderColors.surfaceHover : CiderColors.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(selectedCategory == .account ? CiderColors.borderSelected : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open account profile")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(SettingsCategory.primaryCategories, id: \.self) { category in
                        SettingsPrimaryCategoryButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Cider")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.secondary)

                Text("Settings")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .background(CiderColors.surfaceSubtle)
    }
}

private struct SidebarTrafficLightButton: View {
    let color: NSColor
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: NotesDesign.trafficLightDiameter, height: NotesDesign.trafficLightDiameter)
                .frame(width: NotesDesign.trafficLightTapTarget, height: NotesDesign.trafficLightTapTarget)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SettingsPrimaryCategoryButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: category.icon)
                    .font(CiderFont.bodyMedium)
                Text(category.rawValue)
                    .font(CiderFont.labelMedium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? CiderColors.borderSelected : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsSubcategoryHeader: View {
    let category: SettingsCategory
    @Binding var selectedSubcategory: SettingsSubcategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(category.subcategories, id: \.self) { subcategory in
                    SettingsSubcategoryChip(
                        title: subcategory.title,
                        isSelected: selectedSubcategory == subcategory,
                        action: { selectedSubcategory = subcategory }
                    )
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

private struct SettingsSubcategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CiderFont.labelMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? CiderColors.surfaceHover : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(isSelected ? CiderColors.borderSelected : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsAccountOverviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Account") {
                HStack(spacing: Spacing.md) {
                    Circle()
                        .fill(CiderColors.accentMedium)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(CiderFont.displaySemibold)
                                .foregroundColor(CiderColors.controlAccent)
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Local Account")
                            .font(CiderFont.headingSemibold)
                            .foregroundColor(CiderColors.primary)

                        Text("Not signed in")
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.secondary)
                    }
                }

                Text("Account sync, profile details, and connected services will appear here.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)

                HStack(spacing: Spacing.sm) {
                    Button(action: {}) {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(CiderAccentButtonStyle())

                    Button(action: {}) {
                        Label("Manage Account", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(CiderAccentButtonStyle())
                    .disabled(true)
                    .opacity(CiderColors.disabledOpacity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsSizeOptionButton: View {
    let title: String
    let preview: String?
    let previewSize: CGFloat?
    let isSelected: Bool
    let action: () -> Void
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                if let preview, let previewSize {
                    Text(preview)
                        .font(.system(size: previewSize, weight: .medium))
                        .frame(width: 50, height: 32)
                } else if let icon {
                    Image(systemName: icon)
                        .font(CiderFont.display)
                        .frame(width: 50, height: 32)
                }

                Text(title)
                    .font(CiderFont.caption)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.surfaceInput : CiderColors.surfaceHighlight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.controlAccent : CiderColors.surfaceHover, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsBackgroundView: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueBackground
        } else {
            acrylicBackground
        }
    }

    @ViewBuilder
    private var acrylicBackground: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            CiderColors.acrylicTint
            CiderColors.surfaceHighlight
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                .padding(CiderBorder.innerStrokeInset)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 6)
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.separatorStrong, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
    }
}

// MARK: - Clipboard Storage Settings

private struct ClipboardStorageSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var storageDisplay: String = ""
    @State private var imageStorageDisplay: String = ""
    @State private var showClearConfirmation = false
    @State private var showPurgeConfirmation = false

    private static let retentionOptions: [(label: String, days: Int)] = [
        ("Forever", 0),
        ("1 day", 1),
        ("3 days", 3),
        ("7 days", 7),
        ("14 days", 14),
        ("30 days", 30),
        ("90 days", 90),
    ]

    private static let imageRetentionOptions: [(label: String, days: Int)] = [
        ("1 day", 1),
        ("3 days", 3),
        ("7 days", 7),
        ("14 days", 14),
        ("30 days", 30),
        ("90 days", 90),
        ("Forever", 0),
    ]

    private static let storageLimitOptions: [(label: String, mb: Int)] = [
        ("100 MB", 100),
        ("250 MB", 250),
        ("500 MB", 500),
        ("1 GB", 1000),
        ("2 GB", 2000),
        ("Unlimited", 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Text Retention") {
                SettingsPickerRow(
                    title: "Keep text items for",
                    subtitle: "How long to keep URLs and text in clipboard history",
                    selection: Binding(
                        get: { viewModel.clipboardRetentionDays },
                        set: { viewModel.clipboardRetentionDays = $0 }
                    ),
                    options: Self.retentionOptions.map(\.days),
                    label: { days in Self.retentionOptions.first(where: { $0.days == days })?.label ?? "\(days)d" }
                )
            }

            SettingsSection(title: "Image Retention") {
                SettingsPickerRow(
                    title: "Keep image items for",
                    subtitle: "How long to keep copied images in clipboard history",
                    selection: Binding(
                        get: { viewModel.clipboardImageRetentionDays },
                        set: { viewModel.clipboardImageRetentionDays = $0 }
                    ),
                    options: Self.imageRetentionOptions.map(\.days),
                    label: { days in Self.imageRetentionOptions.first(where: { $0.days == days })?.label ?? "\(days)d" }
                )

                SettingsPickerRow(
                    title: "Max image storage",
                    subtitle: "Oldest images are removed when this limit is exceeded",
                    selection: Binding(
                        get: { viewModel.clipboardMaxImageStorageMB },
                        set: { viewModel.clipboardMaxImageStorageMB = $0 }
                    ),
                    options: Self.storageLimitOptions.map(\.mb),
                    label: { mb in Self.storageLimitOptions.first(where: { $0.mb == mb })?.label ?? "\(mb) MB" }
                )
            }

            SettingsSection(title: "Storage Usage") {
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total: \(storageDisplay)")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.primary)
                        Text("Images: \(imageStorageDisplay)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                    }

                    Spacer()

                    Button("Purge Saved") {
                        showPurgeConfirmation = true
                    }
                    .controlSize(.small)
                    .help("Remove all items marked as saved")

                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                    .controlSize(.small)
                    .help("Delete all clipboard history")
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { refreshStorageDisplay() }
        .onReceive(ClipboardStorage.shared.$items) { _ in
            refreshStorageDisplay()
        }
        .alert("Clear Clipboard History", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) {
                ClipboardStorage.shared.clearAll()
                refreshStorageDisplay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all clipboard history items. This cannot be undone.")
        }
        .alert("Purge Saved Items", isPresented: $showPurgeConfirmation) {
            Button("Purge", role: .destructive) {
                ClipboardStorage.shared.purgeSavedItems()
                refreshStorageDisplay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all items that have been saved as bookmarks or notes from clipboard history.")
        }
    }

    private func refreshStorageDisplay() {
        let total = ClipboardStorage.shared.totalStorageBytes()
        let images = ClipboardStorage.shared.imageStorageBytes()
        storageDisplay = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        imageStorageDisplay = ByteCountFormatter.string(fromByteCount: images, countStyle: .file)
    }
}

// MARK: - Keyboard Shortcuts Reference

private struct KeyboardShortcutsReferenceView: View {
    private struct ShortcutEntry: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private struct ShortcutGroup: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [ShortcutEntry]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Panel", shortcuts: [
            ShortcutEntry(keys: "Option ⌥  double-tap", description: "Toggle Cider panel"),
            ShortcutEntry(keys: "Escape", description: "Clear search → close editor → clear selection → dismiss panel"),
        ]),
        ShortcutGroup(title: "Capture", shortcuts: [
            ShortcutEntry(keys: "⌥B", description: "Capture bookmark from active browser"),
            ShortcutEntry(keys: "⌥⇧B", description: "Quick-save active browser tab"),
            ShortcutEntry(keys: "⌥N", description: "Quick-capture note"),
            ShortcutEntry(keys: "⌥V", description: "Toggle clipboard panel"),
            ShortcutEntry(keys: "⌥⌘2", description: "Screen capture with OCR"),
        ]),
        ShortcutGroup(title: "Navigation", shortcuts: [
            ShortcutEntry(keys: "⌘K", description: "Quick actions palette"),
            ShortcutEntry(keys: "↑ ↓ ← →", description: "Move focus in grid / list"),
            ShortcutEntry(keys: "⇧ + Arrow", description: "Extend selection"),
            ShortcutEntry(keys: "Tab / ⇧Tab", description: "Next / previous item"),
            ShortcutEntry(keys: "Return", description: "Open focused item"),
            ShortcutEntry(keys: "Space", description: "Toggle selection on focused item"),
        ]),
        ShortcutGroup(title: "Editing", shortcuts: [
            ShortcutEntry(keys: "⌘A", description: "Select all items"),
            ShortcutEntry(keys: "⌘C", description: "Copy"),
            ShortcutEntry(keys: "⌘V", description: "Paste"),
            ShortcutEntry(keys: "⌘X", description: "Cut"),
            ShortcutEntry(keys: "⌘Z", description: "Undo"),
            ShortcutEntry(keys: "Delete", description: "Trash focused or selected items"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ForEach(groups) { group in
                SettingsSection(title: group.title) {
                    ForEach(group.shortcuts) { shortcut in
                        HStack(alignment: .firstTextBaseline) {
                            Text(shortcut.keys)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(CiderColors.controlAccent)
                                .frame(width: 170, alignment: .leading)

                            Text(shortcut.description)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Spacer()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
