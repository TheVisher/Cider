import SwiftUI
import AppKit

extension CiderPanelView {

    // MARK: - Section Toggles

    var folderHasSubFolders: Bool {
        guard let folderID = selectedFolderID else { return false }
        return bookmarksViewModel.folders.contains(where: { $0.parentID == folderID })
    }

    // MARK: - Sidebar Content

    var workspaceSidebar: some View {
        WorkspaceDomainSidebarView(
            selectedDomain: $selectedNavigationDomain,
            domains: WorkspaceNavigationDomain.allCases,
            onSelectDomain: openNavigationDomain
        ) {
            folderSidebar(folders: contextualFolders)
        }
    }

    var contextualFolders: [Folder] {
        WorkspaceDomainFolderPolicy.folders(bookmarksViewModel.folders, for: selectedNavigationDomain)
    }

    func folderSidebar(folders visibleFolders: [Folder]) -> some View {
        FolderSidebarView(
            folders: visibleFolders,
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
            },
            onOpenTagManager: {
                openOrSelectTagTab()
            }
        )
    }

    func openNavigationDomain(_ domain: WorkspaceNavigationDomain) {
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()

        if domain == .aiAssistant {
            openOrSelectAIAssistantTab()
            return
        }

        normalizeSelectedTabForCurrentDomain()
    }

    func normalizeSelectedTabForCurrentDomain() {
        let tabs = contextualTabs
        if let selectedTab, tabs.contains(selectedTab) { return }
        selectedTab = tabs.first
    }
}
