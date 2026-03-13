import SwiftUI
import AppKit

extension CiderPanelView {

    // MARK: - Section Toggles

    var folderHasSubFolders: Bool {
        guard let folderID = selectedFolderID else { return false }
        return bookmarksViewModel.folders.contains(where: { $0.parentID == folderID })
    }

    // MARK: - Sidebar Content

    var folderSidebar: some View {
        FolderSidebarView(
            folders: bookmarksViewModel.folders,
            bookmarks: bookmarksViewModel.bookmarks,
            notes: notesViewModel.notes,
            selectedFolderID: $selectedFolderID,
            expandedFolderIDs: $expandedFolderIDs,
            onCreateFolder: { bookmarksViewModel.createFolder(name: $0, parentID: $1) },
            onAssignBookmarkToFolder: { bookmarksViewModel.assign($0, toFolder: $1) },
            onAssignNoteToFolder: { notesViewModel.assignNote($0, toFolder: $1) },
            onRenameFolder: { bookmarksViewModel.renameFolder($0, to: $1) },
            onSetFolderIcon: { VaultFolderService.shared.setIcon($1, for: $0) },
            onDeleteFolder: deleteFolder,
            searchText: $sidebarSearchText,
            onTriggerSearch: { isSearchPaletteVisible = true },
            showBackground: false,
            enableLinkedSources: enableLinkedSources,
            labels: labelStorage.labels,
            selectedTagIDs: $selectedTagIDs,
            tagsCollapsed: $tagsCollapsed,
            onToggleTag: { id in
                if selectedTagIDs.contains(id) {
                    selectedTagIDs.remove(id)
                } else {
                    selectedTagIDs.insert(id)
                    selectedFolderID = nil
                    selectedSourceID = nil
                }
            },
            onClearTags: {
                selectedTagIDs.removeAll()
            },
            onOpenTagManager: {
                openOrSelectTagTab()
            },
            sources: externalSourceStorage.sources,
            selectedSourceID: $selectedSourceID,
            onAddSource: addLinkedSource,
            onSelectSource: { id in
                selectedSourceID = id
                selectedFolderID = nil
                selectedTagIDs.removeAll()
            },
            onToggleSourceTab: { id in
                guard var source = externalSourceStorage.source(for: id) else { return }
                source.isTabPinned.toggle()
                externalSourceStorage.updateSource(source)
            },
            onToggleSourceLibrary: { id in
                guard var source = externalSourceStorage.source(for: id) else { return }
                source.showInLibrary.toggle()
                externalSourceStorage.updateSource(source)
            },
            onRemoveSource: { id in
                if selectedSourceID == id { selectedSourceID = nil }
                externalSourceStorage.removeSource(id)
                // Also close any open tab for this source
                dynamicTabs.removeAll {
                    if case .externalSource(let tabID, _) = $0 { return tabID == id }
                    return false
                }
                if case .externalSource(let tabID, _) = selectedTab, tabID == id {
                    selectedTab = allTabs.first
                }
            }
        )
    }

    func addLinkedSource() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a Folder to Link"
        panel.prompt = "Link Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = externalSourceStorage.addSource(path: url.path, displayName: url.lastPathComponent)
        selectedSourceID = source.id
        selectedFolderID = nil
    }
}
