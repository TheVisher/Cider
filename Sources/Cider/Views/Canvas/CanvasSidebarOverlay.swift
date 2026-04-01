import SwiftUI
import os

/// Frosted glass sidebar that floats over the canvas with equal padding on top, left, and bottom.
/// Embeds the shared FolderSidebarView so it matches the NSPanel sidebar exactly.
struct CanvasSidebarOverlay: View {
    @Binding var isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var bookmarkService = VaultBookmarkService.shared
    @ObservedObject private var notesStorage = NotesStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var sidebarSearchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var tagsCollapsed = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "CanvasSidebarOverlay"
    )

    var body: some View {
        HStack(spacing: 0) {
            if isVisible {
                sidebarContainer
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Spacing.md)
        .padding(.vertical, Spacing.md)
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: isVisible)
    }

    // MARK: - Container

    private var sidebarContainer: some View {
        VStack(spacing: 0) {
            FolderSidebarView(
                folders: VaultFolderService.shared.legacyFolders,
                bookmarks: bookmarkService.bookmarks,
                notes: notesStorage.notes,
                selectedFolderID: $selectedFolderID,
                expandedFolderIDs: $expandedFolderIDs,
                searchText: $sidebarSearchText,
                showBackground: false,
                labels: labelStorage.labels,
                selectedTagIDs: $selectedTagIDs,
                tagsCollapsed: $tagsCollapsed,
                onToggleTag: { id in
                    if selectedTagIDs.contains(id) {
                        selectedTagIDs.remove(id)
                    } else {
                        selectedTagIDs.insert(id)
                        selectedFolderID = nil
                    }
                },
                onClearTags: {
                    selectedTagIDs.removeAll()
                }
            )

            sidebarFooter
        }
        .background {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(color: CiderColors.shadowLight, radius: 8, x: 0, y: 2)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: Spacing.sm) {
            // AI section placeholder
            aiSection

            Divider()
                .background(CiderColors.separator)
                .padding(.bottom, Spacing.xs)

            // Action buttons — same layout as NSPanel footer
            HStack(spacing: Spacing.sm) {
                // Settings gear
                Button {} label: {
                    Image(systemName: "gearshape")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(
                            width: CiderPanelDesign.trafficLightTapTarget,
                            height: CiderPanelDesign.trafficLightTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer(minLength: 0)

                // + New pill
                Button {} label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                        Text("New")
                            .font(CiderFont.bodyMedium)
                    }
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: CiderPanelDesign.trafficLightTapTarget)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Create new item")

                Spacer(minLength: 0)

                // View options
                Button {} label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(
                            width: CiderPanelDesign.trafficLightTapTarget,
                            height: CiderPanelDesign.trafficLightTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("View options")
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
    }

    // MARK: - AI Section

    private var aiSection: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)
            Text("AI")
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(CiderFont.microSemibold)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .padding(.horizontal, Spacing.sm)
    }
}
