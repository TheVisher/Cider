import SwiftUI

extension CiderPanelView {

    // MARK: - Title Bar Content

    @ViewBuilder
    var titleBarContent: some View {
        if isAnyDetailPageMode {
            detailPageTitleBar
        } else if !selectedItemIDs.isEmpty {
            selectionTitleBar
        } else {
            normalTitleBar
        }
    }

    @ViewBuilder
    private var normalTitleBar: some View {
        CiderTabBar(
            selectedTab: $selectedTab,
            tabs: contextualTabs,
            selectedFolderID: $selectedFolderID,
            onCloseTab: closeTab,
            onDeleteTab: deleteTab,
            onReorderTab: reorderVisibleTabs,
            onRenameTab: { id, name in savedViewStorage.renameSavedView(id, to: name) },
            onAddTab: { createSavedViewFromCurrentState() },
            onReopenTab: reopenTab,
            onOpenBoard: { board in
                let savedView = savedViewStorage.createKanbanView(name: board.name, boardID: board.id)
                savedViewStorage.addToTabOrder(savedView.id)
                selectedFolderID = nil
                selectedTab = .savedView(id: savedView.id, name: savedView.name)
            },
            onOpenAIAssistantTab: openOrSelectAIAssistantTab
        )
        .frame(maxWidth: .infinity)

        Image(systemName: "safari")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
            }
            .help("Capture active browser tab")

        Image(systemName: "camera.viewfinder")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .requestScreenCapture, object: nil)
            }
            .help("Capture screen region (\u{2318}\u{2325}2)")

        Image(systemName: "clipboard")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .toggleClipboardViewer, object: nil)
            }
            .help("Clipboard history (\u{2325}V)")

    }

    @ViewBuilder
    private var selectionTitleBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                selectedItemIDs.removeAll()
            }
        } label: {
            Image(systemName: "xmark")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear selection")

        Text("\(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s") selected")
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

        Spacer(minLength: Spacing.sm)

        Menu {
            ForEach(bookmarksViewModel.folders) { folder in
                Button(folder.name) {
                    moveSelectedToFolder(folder.id)
                }
            }
            if !bookmarksViewModel.folders.isEmpty {
                Divider()
            }
            Button("Remove from Folder") {
                moveSelectedToFolder(nil)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionSemibold)
                Text("Move")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move selected items to folder")

        Menu {
            ForEach(CardLabelStorage.shared.labels) { label in
                Button {
                    toggleTagOnSelected(label.id)
                } label: {
                    HStack {
                        if selectedItemsAllHaveLabel(label.id) {
                            Image(systemName: "checkmark")
                        }
                        Circle()
                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                            .frame(width: 8, height: 8)
                        Text(label.name)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tag")
                    .font(CiderFont.captionSemibold)
                Text("Tag")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tag selected items")

        Button {
            deleteSelectedItems()
        } label: {
            Image(systemName: "trash")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.destructive)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete selected items")
    }
}
