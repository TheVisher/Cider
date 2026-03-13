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
            case "clipboard": selectedCategory = .clipboard
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
            .fill(Color.black.opacity(0.55))
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
        .frame(width: 320)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                Color.black.opacity(0.4)
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
}
