import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    var selectedFolderID: UUID?
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var continueSectionCollapsed: Bool

    @State private var config = CiderConfig.load()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Library Items

    /// Continue section always shows global recents regardless of folder selection
    private var continueItems: [LibraryItem] {
        let bookmarkItems = bookmarksViewModel.bookmarks.map { LibraryItem.bookmark($0) }
        let noteItems = notesViewModel.notes.map { LibraryItem.note($0) }
        return (bookmarkItems + noteItems)
            .sorted { $0.date > $1.date }
            .prefix(8)
            .map { $0 }
    }

    /// Library feed filters by folder when one is selected
    private var libraryItems: [LibraryItem] {
        let bookmarks: [Bookmark]
        let notes: [Note]

        if let folderID = selectedFolderID {
            bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            notes = notesViewModel.notes.filter { $0.folderID == folderID }
        } else {
            bookmarks = bookmarksViewModel.bookmarks
            notes = notesViewModel.notes
        }

        let bookmarkItems = bookmarks.map { LibraryItem.bookmark($0) }
        let noteItems = notes.map { LibraryItem.note($0) }
        return (bookmarkItems + noteItems)
            .sorted { $0.date > $1.date }
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private var foldersByID: [UUID: Folder] {
        Dictionary(uniqueKeysWithValues: bookmarksViewModel.folders.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if config.showContinueSection && !continueSectionCollapsed && !continueItems.isEmpty {
                ContinueSectionView(
                    items: continueItems,
                    onOpenBookmark: { bookmarksViewModel.open($0) },
                    onOpenNote: { note in
                        NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                    }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }

            if libraryItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    libraryFeed
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .padding(Spacing.xxs)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }
        }
    }

    // MARK: - Library Feed

    @ViewBuilder
    private var libraryFeed: some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(libraryItems) { item in
                    libraryListRow(item)
                }
            }

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .grid)
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .masonry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - List Row

    @ViewBuilder
    private func libraryListRow(_ item: LibraryItem) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkListRow(
                bookmark: bookmark,
                searchText: "",
                cardSizing: cardSizing.bookmarkSizing,
                folders: bookmarksViewModel.folders,
                onShowDetails: { bookmarksViewModel.open(bookmark) },
                onOpen: { bookmarksViewModel.open(bookmark) },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) }
            )
        case .note(let note):
            NoteListRow(
                note: note,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: bookmarksViewModel.folders,
                isSelected: false,
                onOpen: {
                    NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                },
                onRename: { newTitle in
                    NotesStorage.shared.rename(note: note, to: newTitle)
                },
                onDelete: {
                    notesViewModel.deleteNotes([note])
                },
                onMoveToFolder: { folderID in
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                }
            )
        }
    }

    // MARK: - Card (Grid / Masonry)

    @ViewBuilder
    private func libraryCard(_ item: LibraryItem, mode: BookmarkCard.CardMode) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: mode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.bookmarkSizing,
                folders: bookmarksViewModel.folders,
                onShowDetails: { bookmarksViewModel.open(bookmark) },
                onOpen: { bookmarksViewModel.open(bookmark) },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) }
            )
        case .note(let note):
            NoteCardView(
                note: note,
                mode: mode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: bookmarksViewModel.folders,
                onOpen: {
                    NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                },
                onRename: { newTitle in
                    NotesStorage.shared.rename(note: note, to: newTitle)
                },
                onDelete: {
                    notesViewModel.deleteNotes([note])
                },
                onMoveToFolder: { folderID in
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            Image(systemName: selectedFolderID != nil ? "folder" : "tray.2")
                .font(CiderFont.heroDisplay(scale: 1.0))
                .foregroundColor(CiderColors.tertiary)

            Text(selectedFolderID != nil ? "No items in this folder" : "Your library is empty")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)

            Text(selectedFolderID != nil
                ? "Drag bookmarks or notes into this folder to organize them"
                : "Capture a bookmark or create a note to get started")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func folderName(for note: Note) -> String? {
        guard let folderID = note.folderID else { return nil }
        return foldersByID[folderID]?.name
    }
}
