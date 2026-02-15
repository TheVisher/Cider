import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var pinnedAppsViewModel: PinnedAppsViewModel
    @ObservedObject var commandPaletteViewModel: CommandPaletteViewModel
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedCategory: SettingsCategory = .general
    @State private var selectedSubcategory: SettingsSubcategory = .startup
    @State private var showOnScreen: ShowOnScreenOption = .mouseScreen

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
                    .opacity(0.28)

                VStack(spacing: 0) {
                    SettingsSubcategoryHeader(
                        category: selectedCategory,
                        selectedSubcategory: $selectedSubcategory
                    )
                    .padding(.horizontal, Spacing.md)
                    .frame(height: SettingsDesign.headerHeight)

                    Divider()
                        .opacity(0.22)

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
        .environmentObject(pinnedAppsViewModel)
        .environmentObject(commandPaletteViewModel)
        .onAppear {
            syncSelectedSubcategory(reset: true)
        }
        .onChange(of: selectedCategory) { _, _ in
            syncSelectedSubcategory(reset: true)
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
                        subtitle: "How to open the command palette",
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

        case .paletteBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Palette Behavior") {
                    SettingsToggleRow(
                        title: "Remember palette state",
                        subtitle: "Keep folders open between palette sessions",
                        isOn: $viewModel.rememberPaletteState
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .notesBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Notes Behavior") {
                    SettingsToggleRow(
                        title: "Option+N to open notes",
                        subtitle: "Quick-launch floating notes panel",
                        isOn: $viewModel.enableNotesHotkey
                    )

                    SettingsToggleRow(
                        title: "Remember note window position",
                        subtitle: "Reopen each note where you last closed it",
                        isOn: $viewModel.rememberNotesPanelPositionPerNote
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

        case .notesStorage:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Storage") {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Notes directory")
                                .font(.body)
                                .foregroundColor(CiderColors.primary)

                            Text(viewModel.notesDirectory)
                                .font(.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseNotesDirectory()
                        }
                        .controlSize(.small)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .windowCycling:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Window Cycling") {
                    SettingsToggleRow(
                        title: "Option+Tab to cycle windows",
                        subtitle: "Quick window switching like Cmd+Tab",
                        isOn: $viewModel.enableOptionTabCycling
                    )

                    if viewModel.enableOptionTabCycling {
                        SettingsToggleRow(
                            title: "Cycle windows on all screens",
                            subtitle: "Include windows from all displays",
                            isOn: $viewModel.optionTabCycleAllScreens
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .windowBehavior:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Window Behavior") {
                    SettingsToggleRow(
                        title: "Auto-hide inactive apps",
                        subtitle: "Hide other apps when focusing a window (like Stage Manager)",
                        isOn: $viewModel.autoHideApps
                    )

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Show Cider on")
                            .font(.body)
                            .foregroundColor(CiderColors.primary)

                        Picker("", selection: $showOnScreen) {
                            ForEach(ShowOnScreenOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: SettingsDesign.displayPickerMaxWidth, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .tilingHotkeys:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Tiling Shortcuts") {
                    SettingsToggleRow(
                        title: "Tiling hotkeys (Ctrl+Option)",
                        subtitle: "Rectangle-style shortcuts to tile windows",
                        isOn: $viewModel.enableTilingHotkeys
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .tilingDynamic:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Dynamic Tiling") {
                    SettingsToggleRow(
                        title: "Dynamic tiling",
                        subtitle: "Auto-pair windows when tiling to half zones",
                        isOn: $viewModel.enableDynamicTiling
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .bookmarksManage:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Bookmarks") {
                    SettingsToggleRow(
                        title: "Option+B to open bookmarks",
                        subtitle: "Quick-launch floating bookmarks panel",
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
                    .opacity(viewModel.autoCaptureCopiedURLs ? 1.0 : 0.55)

                    SettingsToggleRow(
                        title: "Remember bookmarks window position",
                        subtitle: "Reopen bookmarks where you last left it",
                        isOn: $viewModel.rememberBookmarksPanelPosition
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

                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Bookmarks directory")
                                .font(.body)
                                .foregroundColor(CiderColors.primary)

                            Text(viewModel.bookmarksDirectory)
                                .font(.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Choose...") {
                            chooseBookmarksDirectory()
                        }
                        .controlSize(.small)
                    }
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

        case .appearanceWindow:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Window Size") {
                    HStack(spacing: Spacing.md) {
                        ForEach(PaletteSize.allCases, id: \.self) { size in
                            SettingsSizeOptionButton(
                                title: size.displayName,
                                preview: nil,
                                previewSize: nil,
                                isSelected: viewModel.paletteSize == size,
                                action: { viewModel.paletteSize = size },
                                icon: windowIcon(for: size)
                            )
                        }
                    }

                    Text("Changes apply when you reopen the command palette")
                        .font(.caption)
                        .foregroundColor(CiderColors.tertiary)
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

        case .advancedAccessibility:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Accessibility") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Button(action: openAccessibilityPreferences) {
                            Label("Open Accessibility Settings", systemImage: "hand.raised")
                        }
                        .buttonStyle(SettingsButtonStyle())

                        Text("Cider requires accessibility permissions to manage windows.")
                            .font(.caption)
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
                        .buttonStyle(SettingsDestructiveButtonStyle())

                        Text("This will reset all settings to their default values.")
                            .font(.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
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

    private func chooseBookmarksDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a directory for Cider bookmarks"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.bookmarksDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.bookmarksDirectory = path
            }
        }
    }

    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func windowIcon(for size: PaletteSize) -> String {
        switch size {
        case .small:
            "rectangle.portrait"
        case .medium:
            "rectangle"
        case .large:
            "rectangle.expand.vertical"
        }
    }
}

private enum SettingsCategory: String, CaseIterable {
    case general = "General"
    case notes = "Notes"
    case windowing = "Windowing"
    case tiling = "Tiling"
    case bookmarks = "Bookmarks"
    case appearance = "Appearance"
    case advanced = "Advanced"
    case about = "About"
    case account = "Account"

    static var primaryCategories: [SettingsCategory] {
        [.general, .notes, .windowing, .tiling, .bookmarks, .appearance, .advanced, .about]
    }

    var icon: String {
        switch self {
        case .general:
            "gearshape"
        case .notes:
            "note.text"
        case .windowing:
            "macwindow.on.rectangle"
        case .tiling:
            "rectangle.split.2x1"
        case .bookmarks:
            "square.grid.2x2"
        case .appearance:
            "paintbrush"
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
            [.startup, .activation, .paletteBehavior]
        case .notes:
            [.notesBehavior, .notesEditor, .notesStorage]
        case .windowing:
            [.windowCycling, .windowBehavior]
        case .tiling:
            [.tilingHotkeys, .tilingDynamic]
        case .bookmarks:
            [.bookmarksManage]
        case .appearance:
            [.appearanceText, .appearanceWindow, .appearanceMenuBar]
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
    case paletteBehavior
    case notesBehavior
    case notesEditor
    case notesStorage
    case windowCycling
    case windowBehavior
    case tilingHotkeys
    case tilingDynamic
    case bookmarksManage
    case appearanceText
    case appearanceWindow
    case appearanceMenuBar
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
        case .paletteBehavior:
            "Palette Behavior"
        case .notesBehavior:
            "Behavior"
        case .notesEditor:
            "Editor"
        case .notesStorage:
            "Storage"
        case .windowCycling:
            "Cycling"
        case .windowBehavior:
            "Behavior"
        case .tilingHotkeys:
            "Shortcuts"
        case .tilingDynamic:
            "Dynamic Tiling"
        case .bookmarksManage:
            "Manage"
        case .appearanceText:
            "Text"
        case .appearanceWindow:
            "Window Size"
        case .appearanceMenuBar:
            "Menu Bar"
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
    static let shadowPadding: CGFloat = 45
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
                        .fill(CiderColors.controlAccent.opacity(0.22))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(CiderColors.controlAccent)
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Local Account")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)

                        Text("Profile settings")
                            .font(.system(size: 11))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(selectedCategory == .account ? Color.white.opacity(0.11) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(selectedCategory == .account ? 0.14 : 0), lineWidth: 1)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CiderColors.secondary)

                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundColor(CiderColors.tertiary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .background(Color.white.opacity(0.035))
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
                    .font(.system(size: 11, weight: .medium))
                Text(category.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.14 : 0), lineWidth: 1)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.14 : 0), lineWidth: 1)
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
                        .fill(CiderColors.controlAccent.opacity(0.2))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(CiderColors.controlAccent)
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Local Account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(CiderColors.primary)

                        Text("Not signed in")
                            .font(.system(size: 12))
                            .foregroundColor(CiderColors.secondary)
                    }
                }

                Text("Account sync, profile details, and connected services will appear here.")
                    .font(.caption)
                    .foregroundColor(CiderColors.tertiary)

                HStack(spacing: Spacing.sm) {
                    Button(action: {}) {
                        Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(SettingsButtonStyle())

                    Button(action: {}) {
                        Label("Manage Account", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(true)
                    .opacity(0.55)
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
                        .font(.system(size: 20))
                        .frame(width: 50, height: 32)
                }

                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.controlAccent : Color.white.opacity(0.1), lineWidth: 1)
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: 18)
                .offset(y: 18)
                .opacity(0.7)

            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Color.black.opacity(0.45)
                Color.white.opacity(0.03)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.separator.opacity(0.5), lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
    }
}
