import SwiftUI

struct CiderTabBar: View {
    @Binding var selectedTab: CiderTab?
    let tabs: [CiderTab]
    @Binding var selectedFolderID: UUID?
    @Binding var selectedSourceID: UUID?
    var onCloseTab: ((CiderTab) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onRenameTab: ((UUID, String) -> Void)?
    var onAddTab: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var externalSourceRegistry = ExternalSourceRegistry.shared
    @ObservedObject private var dateCardStorage = DateCardStorage.shared

    @State private var draggingTabID: String?
    @State private var renamingTabID: UUID?
    @State private var renameText: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CiderPanelDesign.tabSpacing) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    tabButton(for: tab, at: index)
                }

                if let onAddTab {
                    addTabButton(action: onAddTab)
                }
            }
            .padding(.horizontal, CiderPanelDesign.tabHorizontalPadding)
        }
        .frame(height: CiderPanelDesign.tabBarHeight)
    }

    @ViewBuilder
    private func tabButton(for tab: CiderTab, at index: Int) -> some View {
        let isSelected = selectedTab == tab && selectedFolderID == nil && selectedSourceID == nil
        let count = badgeCount(for: tab)
        let isDragging = draggingTabID == tab.id

        Button {
            withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                selectedFolderID = nil
                selectedSourceID = nil
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(CiderFont.bodyMedium)

                if renamingTabID == tab.savedViewID, let savedViewID = tab.savedViewID {
                    TextField("", text: $renameText, onCommit: {
                        commitRename(savedViewID)
                    })
                    .textFieldStyle(.plain)
                    .font(isSelected ? CiderFont.labelSemibold : CiderFont.label)
                    .frame(minWidth: 40, maxWidth: 120)
                    .focused($isRenameFieldFocused)
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        isRenameFieldFocused = true
                    }
                } else {
                    Text(tab.displayName)
                        .font(isSelected ? CiderFont.labelSemibold : CiderFont.label)
                        .lineLimit(1)
                }

                if count > 0 {
                    Text("\(count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                        .padding(.horizontal, CiderPanelDesign.tabBadgePadding)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? CiderColors.separatorFirm : CiderColors.separatorLight)
                        )
                }
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.separatorMedium : Color.clear)
            )
            .contentShape(Rectangle())
            .opacity(isDragging ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if let savedViewID = tab.savedViewID {
                    renameText = tab.displayName
                    renamingTabID = savedViewID
                }
            }
        )
        .contextMenu {
            if tab.savedViewID != nil {
                Button("Rename Tab") {
                    if let savedViewID = tab.savedViewID {
                        renameText = tab.displayName
                        renamingTabID = savedViewID
                    }
                }
            }
            Button("Close Tab") {
                onCloseTab?(tab)
            }
        }
        .onDrag {
            draggingTabID = tab.id
            return NSItemProvider(object: tab.id as NSString)
        }
        .onDrop(of: [.text], delegate: TabReorderDropDelegate(
            tabID: tab.id,
            tabIndex: index,
            tabs: tabs,
            draggingTabID: $draggingTabID,
            onReorder: onReorderTab
        ))
    }

    private func addTabButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: "plus")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tab")
    }

    private func commitRename(_ savedViewID: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRenameTab?(savedViewID, trimmed)
        }
        renamingTabID = nil
        renameText = ""
    }

    private func badgeCount(for tab: CiderTab) -> Int {
        switch tab {
        case .savedView(let id, _):
            // Show urgent date card count on the first (Home) tab
            guard tabs.first?.savedViewID == id else { return 0 }
            return dateCardStorage.dateCards.filter { $0.urgency() != nil }.count
        case .search: return 0
        case .externalSource(let id, _): return externalSourceRegistry.files(for: id).count
        case .tag: return 0
        case .aiChat: return 0
        }
    }
}

// MARK: - Drop Delegate for Reordering

private struct TabReorderDropDelegate: DropDelegate {
    let tabID: String
    let tabIndex: Int
    let tabs: [CiderTab]
    @Binding var draggingTabID: String?
    var onReorder: ((Int, Int) -> Void)?

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingTabID,
              draggingID != tabID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == draggingID }) else { return }
        onReorder?(sourceIndex, tabIndex)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTabID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingTabID != nil
    }
}
