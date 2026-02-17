import AppKit
import SwiftUI

struct NotesBrowserView: View {
    let notes: [Note]
    let folders: [Folder]
    @Binding var displayMode: NoteDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var selectedItemIDs: Set<String>
    let searchText: String
    var selectedNoteID: UUID?
    let onOpenNote: (Note) -> Void
    let onRenameNote: (Note, String) -> Void
    let onDeleteNote: (Note) -> Void
    let onMoveNoteToFolder: (Note, UUID?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectionAnchorID: String?

    private var cardSizing: NoteCardSizing {
        NoteCardSizing(scale: cardSizeScale)
    }

    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
    }

    private var foldersByID: [UUID: Folder] {
        Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
    }

    private func folderName(for note: Note) -> String? {
        guard let folderID = note.folderID else { return nil }
        return foldersByID[folderID]?.name
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xxs)
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(notes) { note in
                    noteListRow(note: note)
                }
            }

        case .grid:
            LazyVGrid(columns: cardColumns, spacing: Spacing.md) {
                ForEach(notes) { note in
                    noteCard(note: note, mode: .grid)
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(notes) { note in
                    noteCard(note: note, mode: .masonry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - Selection Helpers

    private func itemID(for note: Note) -> String {
        "note-\(note.id.uuidString)"
    }

    private func isNoteSelected(_ note: Note) -> Bool {
        selectedItemIDs.contains(itemID(for: note))
    }

    private func handleSelect(note: Note) {
        let id = itemID(for: note)
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
    }

    private func handleShiftSelect(note: Note) {
        let id = itemID(for: note)
        guard let anchorID = selectionAnchorID,
              let anchorIndex = notes.firstIndex(where: { itemID(for: $0) == anchorID }),
              let clickedIndex = notes.firstIndex(where: { $0.id == note.id }) else {
            selectedItemIDs.insert(id)
            selectionAnchorID = id
            return
        }

        let range = min(anchorIndex, clickedIndex) ... max(anchorIndex, clickedIndex)
        for i in range {
            selectedItemIDs.insert(itemID(for: notes[i]))
        }
    }

    private func handleNormalAction(_ action: () -> Void) {
        if !selectedItemIDs.isEmpty {
            selectedItemIDs.removeAll()
        } else {
            action()
        }
    }

    // MARK: - Card/Row Builders

    private func noteCard(note: Note, mode: NoteCardView.NoteCardMode) -> some View {
        NoteCardView(
            note: note,
            mode: mode,
            cardSizing: cardSizing,
            searchText: searchText,
            folderName: folderName(for: note),
            folders: folders,
            onOpen: { handleNormalAction { onOpenNote(note) } },
            onRename: { onRenameNote(note, $0) },
            onDelete: { onDeleteNote(note) },
            onMoveToFolder: { onMoveNoteToFolder(note, $0) },
            dragProvider: noteDragProvider(for: note),
            dragPreviewOverride: multiDragPreview(for: note),
            isSelected: isNoteSelected(note),
            onSelect: { handleSelect(note: note) },
            onShiftSelect: { handleShiftSelect(note: note) }
        )
    }

    private func noteListRow(note: Note) -> some View {
        NoteListRow(
            note: note,
            cardSizing: cardSizing,
            searchText: searchText,
            folderName: folderName(for: note),
            folders: folders,
            isSelected: isNoteSelected(note) || selectedNoteID == note.id,
            onOpen: { handleNormalAction { onOpenNote(note) } },
            onRename: { onRenameNote(note, $0) },
            onDelete: { onDeleteNote(note) },
            onMoveToFolder: { onMoveNoteToFolder(note, $0) },
            dragProvider: noteDragProvider(for: note),
            dragPreviewOverride: multiDragPreview(for: note),
            onSelect: { handleSelect(note: note) },
            onShiftSelect: { handleShiftSelect(note: note) }
        )
    }

    // MARK: - Drag Provider

    private func noteDragProvider(for note: Note) -> () -> NSItemProvider {
        return {
            let noteItemID = itemID(for: note)

            if selectedItemIDs.contains(noteItemID) && selectedItemIDs.count > 1 {
                let allItems = CiderMultiDrag.parseSelectedItemIDs(selectedItemIDs)
                return CiderMultiDrag.makeProvider(
                    primaryType: NoteDragPayload.typeIdentifier,
                    primaryID: note.id,
                    allItemIDs: allItems
                )
            } else {
                let provider = NSItemProvider(
                    object: "\(NoteDragPayload.textPrefix)\(note.id.uuidString)" as NSString
                )
                let payload = Data(note.id.uuidString.utf8)
                provider.registerDataRepresentation(
                    forTypeIdentifier: NoteDragPayload.typeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(payload, nil)
                    return nil
                }
                return provider
            }
        }
    }

    private func multiDragPreview(for note: Note) -> AnyView? {
        guard isNoteSelected(note), selectedItemIDs.count > 1 else { return nil }

        var items: [MultiDragPreviewItem] = [.note(note)]
        for n in notes where isNoteSelected(n) && n.id != note.id {
            items.append(.note(n))
            if items.count >= 3 { break }
        }

        return AnyView(MultiDragPreview(items: items, totalCount: selectedItemIDs.count))
    }
}
