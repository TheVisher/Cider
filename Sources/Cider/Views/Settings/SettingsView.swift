import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory = .general
    @State private var selectedSubcategory: SettingsSubcategory = .startup

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
        .onReceive(NotificationCenter.default.publisher(for: .settingsNavigate)) { notification in
            guard let category = notification.userInfo?["category"] as? String else { return }
            switch category {
            case "data": selectedCategory = .data
            case "general": selectedCategory = .general
            case "appearance": selectedCategory = .appearance
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
                SettingsSection(title: "Directories") {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Cider data")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Text(viewModel.ciderDataDirectory)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)

                            Text("Bookmarks, contacts, stacks, labels, date cards, saved views")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseCiderDataDirectory()
                        }
                        .controlSize(.small)
                    }

                    Divider()
                        .opacity(CiderColors.dividerSecondaryOpacity)

                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Notes")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)

                            Text(viewModel.notesDirectory)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)

                            Text("Note files (.md)")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseNotesDirectory()
                        }
                        .controlSize(.small)
                    }

                    Divider()
                        .opacity(CiderColors.dividerSecondaryOpacity)

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

    private func chooseNotesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a directory for Cider notes"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.notesDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.notesDirectory = path
            }
        }
    }

    private func chooseCiderDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a directory for Cider data"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.ciderDataDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.ciderDataDirectory = path
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
    case data = "Data"
    case intelligence = "Intelligence"
    case advanced = "Advanced"
    case about = "About"
    case account = "Account"

    static var primaryCategories: [SettingsCategory] {
        [.general, .notes, .bookmarks, .appearance, .intelligence, .data, .advanced, .about]
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
            [.startup, .activation, .panelBehavior, .features]
        case .notes:
            [.notesBehavior, .notesEditor]
        case .bookmarks:
            [.bookmarksBehavior]
        case .appearance:
            [.appearanceText, .appearanceMenuBar, .appearanceSounds]
        case .intelligence:
            [.intelligenceFeatures]
        case .data:
            [.dataDirectories, .dataTrash, .dataNotifications]
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
    case dataDirectories
    case dataTrash
    case dataNotifications
    case intelligenceFeatures
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
        case .dataDirectories:
            "Directories"
        case .dataTrash:
            "Trash"
        case .dataNotifications:
            "Notifications"
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
