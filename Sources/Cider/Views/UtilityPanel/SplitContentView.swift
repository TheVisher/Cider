import SwiftUI

struct SplitContentView: View {
    let item1: UtilityPanelActiveItem
    let item2: UtilityPanelActiveItem
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    @State private var leftFraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let dividerW = UtilityPanelDesign.splitDividerWidth
            let usable = totalWidth - dividerW
            let leftWidth = max(UtilityPanelDesign.splitMinPaneWidth, usable * leftFraction)
            let rightWidth = max(UtilityPanelDesign.splitMinPaneWidth, usable - leftWidth)

            HStack(spacing: 0) {
                paneView(for: item1)
                    .frame(width: leftWidth)
                    .clipped()

                divider(totalWidth: totalWidth, totalHeight: geo.size.height)

                paneView(for: item2)
                    .frame(width: rightWidth)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private func paneView(for item: UtilityPanelActiveItem) -> some View {
        switch item {
        case .bookmark(let id):
            UtilityPanelBookmarkDetail(
                bookmarkID: id,
                bookmarksViewModel: bookmarksViewModel,
                compact: true
            )
        case .note(let id):
            SplitNotePreview(noteID: id)
        case .todo(let id):
            UtilityPanelTodoDetail(todoID: id)
        }
    }

    private func divider(totalWidth: CGFloat, totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(CiderColors.borderSubtle)
            .frame(width: UtilityPanelDesign.splitDividerWidth)
            .padding(.horizontal, (UtilityPanelDesign.splitDividerGrabWidth - UtilityPanelDesign.splitDividerWidth) / 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation.width / totalWidth
                        let newFraction = dragStartFraction + delta
                        let minFrac = UtilityPanelDesign.splitMinPaneWidth / totalWidth
                        leftFraction = min(max(newFraction, minFrac), 1.0 - minFrac)
                    }
                    .onEnded { _ in
                        dragStartFraction = leftFraction
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Read-Only Note Preview for Split View

/// Renders note content as plain text in a scrollable view.
/// Used instead of InlineNoteEditorView in split mode because the TipTap
/// editor shares a single selectedNote on NotesViewModel — two editors
/// would fight over which note is selected.
private struct SplitNotePreview: View {
    let noteID: UUID

    @ObservedObject private var notesStorage = NotesStorage.shared

    private var note: Note? {
        notesStorage.notes.first(where: { $0.id == noteID })
    }

    var body: some View {
        if let note {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(note.title)
                        .font(CiderFont.headingSemibold)
                        .foregroundColor(CiderColors.primary)

                    Text(note.content)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
            }
        } else {
            PlaceholderMode().contentView
        }
    }
}
