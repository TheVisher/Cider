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

                divider(totalWidth: totalWidth)

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
            UtilityPanelNoteDetail(noteID: id, notesViewModel: notesViewModel)
        case .todo(let id):
            UtilityPanelTodoDetail(todoID: id)
        }
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(CiderColors.borderSubtle)
            .frame(width: UtilityPanelDesign.splitDividerWidth)
            .contentShape(Rectangle().size(
                width: UtilityPanelDesign.splitDividerGrabWidth,
                height: 10000
            ))
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
