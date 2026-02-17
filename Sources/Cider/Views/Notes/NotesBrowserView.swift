import AppKit
import SwiftUI

struct NotesBrowserView: View {
    let notes: [Note]
    let folders: [Folder]
    @Binding var displayMode: NoteDisplayMode
    @Binding var cardSizeScale: Double
    let searchText: String
    var selectedNoteID: UUID?
    let onOpenNote: (Note) -> Void
    let onRenameNote: (Note, String) -> Void
    let onDeleteNote: (Note) -> Void
    let onMoveNoteToFolder: (Note, UUID?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    // MARK: - Card/Row Builders

    private func noteCard(note: Note, mode: NoteCardView.NoteCardMode) -> some View {
        NoteCardView(
            note: note,
            mode: mode,
            cardSizing: cardSizing,
            searchText: searchText,
            folderName: folderName(for: note),
            folders: folders,
            onOpen: { onOpenNote(note) },
            onRename: { onRenameNote(note, $0) },
            onDelete: { onDeleteNote(note) },
            onMoveToFolder: { onMoveNoteToFolder(note, $0) },
            dragProvider: noteDragProvider(for: note)
        )
    }

    private func noteListRow(note: Note) -> some View {
        NoteListRow(
            note: note,
            cardSizing: cardSizing,
            searchText: searchText,
            folderName: folderName(for: note),
            folders: folders,
            isSelected: selectedNoteID == note.id,
            onOpen: { onOpenNote(note) },
            onRename: { onRenameNote(note, $0) },
            onDelete: { onDeleteNote(note) },
            onMoveToFolder: { onMoveNoteToFolder(note, $0) },
            dragProvider: noteDragProvider(for: note)
        )
    }

    // MARK: - Drag Provider

    private func noteDragProvider(for note: Note) -> () -> NSItemProvider {
        return {
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
