import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject var viewModel = SettingsViewModel()
    @State var selectedCategory: SettingsCategory = .general
    @State var selectedSubcategory: SettingsSubcategory = .startup
    @State var importResult: String?
    @State var exportResult: String?
    @State var migrationResult: String?
    @State var isMigrating = false
    @State var pendingSubcategory: SettingsSubcategory?
    @State var automaticallyChecksForUpdates = SparkleUpdaterService.shared.automaticallyChecksForUpdates
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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

            if viewModel.showEmptyTrashConfirm {
                emptyTrashConfirmOverlay
            }
        }
        .frame(width: SettingsDesign.width, height: SettingsDesign.height)
        .animation(reduceMotion ? .none : .snappy, value: viewModel.showEmptyTrashConfirm)
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
            if let sub = notification.userInfo?["subcategory"] as? String {
                switch sub {
                case "trash": pendingSubcategory = .dataTrash
                case "directories": pendingSubcategory = .dataDirectories
                default: break
                }
            }
            switch category {
            case "data": selectedCategory = .data
            case "general": selectedCategory = .general
            case "appearance": selectedCategory = .appearance
            case "capture": selectedCategory = .capture
            case "content": selectedCategory = .content
            default: break
            }
        }
    }

    func syncSelectedSubcategory(reset: Bool) {
        let options = selectedCategory.subcategories
        guard let first = options.first else { return }

        if let pending = pendingSubcategory, options.contains(pending) {
            selectedSubcategory = pending
            pendingSubcategory = nil
        } else if reset || !options.contains(selectedSubcategory) {
            selectedSubcategory = first
        }
    }

    @ViewBuilder
    var emptyTrashConfirmOverlay: some View {
        RoundedRectangle(cornerRadius: SettingsDesign.cornerRadius, style: .continuous)
            .fill(CiderColors.overlayBadge)
            .onTapGesture { viewModel.showEmptyTrashConfirm = false }

        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Empty Trash?")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("All items in the trash will be permanently deleted. This cannot be undone.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Spacing.sm) {
                Button("Cancel") {
                    viewModel.showEmptyTrashConfirm = false
                }
                .buttonStyle(CiderSecondaryButtonStyle())

                Button("Empty Trash") {
                    TrashStorage.shared.emptyTrash()
                    NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
                    viewModel.showEmptyTrashConfirm = false
                }
                .buttonStyle(CiderDestructiveButtonStyle())
            }
        }
        .padding(Spacing.xl)
        .frame(width: SettingsDesign.confirmDialogWidth)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                CiderColors.shadowHeavy
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    var overrideableTypes: [StorageType] {
        [.bookmarks, .notes, .contacts, .dateCards, .stacks, .labels, .savedViews, .sources]
    }

    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
    /// Width of inline Picker controls in SettingsPickerRow
    static let inlinePickerWidth: CGFloat = 140
    /// Width of the modal confirmation dialog (e.g. Empty Trash)
    static let confirmDialogWidth: CGFloat = 320
    /// Max width of text input fields in account forms
    static let formFieldMaxWidth: CGFloat = 320
    /// Small avatar circle diameter (sidebar account button)
    static let accountAvatarSmall: CGFloat = 36
    /// Large avatar circle diameter (account overview section)
    static let accountAvatarLarge: CGFloat = 52
    /// Width of the preview area in text-size option buttons
    static let sizeOptionPreviewWidth: CGFloat = 50
    /// Height of the preview area in text-size option buttons
    static let sizeOptionPreviewHeight: CGFloat = 32
    /// Base font size for text-size preview buttons (14pt heading)
    static let textPreviewBaseSize: CGFloat = 14
    /// Width of the keyboard-shortcut key column in the Shortcuts reference table
    static let shortcutKeyColumnWidth: CGFloat = 170
    /// Width of the trash retention picker
    static let retentionPickerWidth: CGFloat = 100
    /// Stroke width for selection-ring overlays on option buttons and sidebar rows
    static let rowStrokeWidth: CGFloat = 1
    /// Minimum tap-target height for subcategory chip buttons in the header
    static let chipMinHeight: CGFloat = 30
    /// Icon column width in trash item rows
    static let trashIconColumnWidth: CGFloat = 16
    /// Width of the About page link button
    static let aboutLinkButtonWidth: CGFloat = 70
    /// Height of the About page link button
    static let aboutLinkButtonHeight: CGFloat = 50
    /// App icon image size in About view
    static let aboutAppIconSize: CGFloat = 64
    /// Drop-shadow blur radius on the settings window chrome
    static let windowShadowRadius: CGFloat = 8
    /// Drop-shadow Y offset on the settings window chrome
    static let windowShadowYOffset: CGFloat = 6
    /// Device icon column width in Connected Devices rows
    static let deviceIconColumnWidth: CGFloat = 20
    /// Intelligence status indicator dot size
    static let intelligenceDotSize: CGFloat = 8
}
