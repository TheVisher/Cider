import SwiftUI

extension SettingsView {

    @ViewBuilder
    var selectedSubcategoryContent: some View {
        switch selectedSubcategory {

        // MARK: - General

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

                    SettingsSliderRow(
                        title: viewModel.activationMode == .doubleTap
                            ? "Double-tap speed"
                            : "Tap speed",
                        value: $viewModel.activationSpeed,
                        range: 0.15...0.5,
                        labels: ("Fast", "Slow")
                    )
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

                    SettingsToggleRow(
                        title: "Open on active display",
                        subtitle: "Show the panel on the screen where your mouse cursor is",
                        isOn: $viewModel.openOnMouseScreen
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

        case .shortcuts:
            KeyboardShortcutsReferenceView()

        // MARK: - Content

        case .contentBookmarks:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Bookmarks") {
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

        case .contentNotes:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Notes") {
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

        // MARK: - Capture

        case .captureBookmarks:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Bookmark Capture") {
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
                        title: "Option+N to create note",
                        subtitle: "Open the panel and start a new note",
                        isOn: $viewModel.enableNotesHotkey
                    )
                }

                SettingsSection(title: "Auto-Capture") {
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
                }

                SettingsSection(title: "Sources") {
                    SettingsToggleRow(
                        title: "Linked Sources",
                        subtitle: "Watch external folders and surface their .md files in Cider",
                        isOn: $viewModel.enableLinkedSources
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .captureClipboard:
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

        case .captureStorage:
            ClipboardStorageSettingsView()
                .environmentObject(viewModel)

        // MARK: - Appearance

        case .appearanceText:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Text Size") {
                    HStack(spacing: Spacing.md) {
                        ForEach(TextSize.allCases, id: \.self) { size in
                            SettingsSizeOptionButton(
                                title: size.displayName,
                                preview: "Aa",
                                previewSize: SettingsDesign.textPreviewBaseSize * size.scale,
                                isSelected: viewModel.textSize == size,
                                action: { viewModel.textSize = size }
                            )
                        }
                    }
                }

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

        case .appearanceToasts:
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        // MARK: - Intelligence

        case .intelligenceFeatures:
            IntelligenceSettingsView()
                .frame(maxWidth: .infinity, alignment: .leading)

        // MARK: - Data

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
                            Text("\(VaultBookmarkService.shared.bookmarks.count) bookmarks")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }

                SettingsSection(title: "Vault Migration") {
                    Text("Export all Cider data as portable vault files. Creates `.webloc` files for bookmarks and only writes legacy sidecar metadata for item types that still need migration fallback. Safe to run multiple times.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    HStack(spacing: Spacing.sm) {
                        Button {
                            isMigrating = true
                            migrationResult = nil
                            Task {
                                let result = await VaultMigrationService.shared.runFullMigration()
                                await MainActor.run {
                                    migrationResult = result.summary
                                    isMigrating = false
                                }
                            }
                        } label: {
                            Label("Export to Vault", systemImage: "shippingbox")
                        }
                        .buttonStyle(CiderSecondaryButtonStyle())
                        .disabled(isMigrating)

                        if isMigrating {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let migrationResult {
                            Text(migrationResult)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        // MARK: - About

        case .aboutOverview:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                AboutSettingsView()

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

        // MARK: - Legacy / Other

        case .syncSettings:
            SyncSettingsView()
                .frame(maxWidth: .infinity, alignment: .leading)

        case .accountOverview:
            SettingsAccountOverviewView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
