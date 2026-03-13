import SwiftUI

// MARK: - Background

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

// MARK: - Primary Sidebar

struct SettingsPrimarySidebar: View {
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

// MARK: - Traffic Light Button

struct SidebarTrafficLightButton: View {
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

// MARK: - Category Button

struct SettingsPrimaryCategoryButton: View {
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

// MARK: - Subcategory Header

struct SettingsSubcategoryHeader: View {
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

// MARK: - Subcategory Chip

struct SettingsSubcategoryChip: View {
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

// MARK: - Account Overview

struct SettingsAccountOverviewView: View {
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

// MARK: - Size Option Button

struct SettingsSizeOptionButton: View {
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

// MARK: - Clipboard Storage Settings

struct ClipboardStorageSettingsView: View {
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

struct KeyboardShortcutsReferenceView: View {
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
            ShortcutEntry(keys: "Option \u{2325}  double-tap", description: "Toggle Cider panel"),
            ShortcutEntry(keys: "Escape", description: "Clear search \u{2192} close editor \u{2192} clear selection \u{2192} dismiss panel"),
        ]),
        ShortcutGroup(title: "Capture", shortcuts: [
            ShortcutEntry(keys: "\u{2325}B", description: "Capture bookmark from active browser"),
            ShortcutEntry(keys: "\u{2325}\u{21E7}B", description: "Quick-save active browser tab"),
            ShortcutEntry(keys: "\u{2325}N", description: "Quick-capture note"),
            ShortcutEntry(keys: "\u{2325}V", description: "Toggle clipboard panel"),
            ShortcutEntry(keys: "\u{2325}\u{2318}2", description: "Screen capture with OCR"),
        ]),
        ShortcutGroup(title: "Navigation", shortcuts: [
            ShortcutEntry(keys: "\u{2318}K", description: "Quick actions palette"),
            ShortcutEntry(keys: "\u{2191} \u{2193} \u{2190} \u{2192}", description: "Move focus in grid / list"),
            ShortcutEntry(keys: "\u{21E7} + Arrow", description: "Extend selection"),
            ShortcutEntry(keys: "Tab / \u{21E7}Tab", description: "Next / previous item"),
            ShortcutEntry(keys: "Return", description: "Open focused item"),
            ShortcutEntry(keys: "Space", description: "Toggle selection on focused item"),
        ]),
        ShortcutGroup(title: "Editing", shortcuts: [
            ShortcutEntry(keys: "\u{2318}A", description: "Select all items"),
            ShortcutEntry(keys: "\u{2318}C", description: "Copy"),
            ShortcutEntry(keys: "\u{2318}V", description: "Paste"),
            ShortcutEntry(keys: "\u{2318}X", description: "Cut"),
            ShortcutEntry(keys: "\u{2318}Z", description: "Undo"),
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
