import SwiftUI
import os

/// Wrapper that renders the appropriate card type for a canvas node
/// and handles drag-to-reposition.
struct CanvasCardView: View {
    let node: CanvasNode
    let zoom: CGFloat
    @ObservedObject var viewModel: CanvasViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovered = false

    private static let logger = Logger(subsystem: "com.cider", category: "CanvasCardView")

    var body: some View {
        cardContent
            .frame(width: node.size.width)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.controlAccent, lineWidth: (node.itemID != nil && viewModel.selectedItemIDs.contains(node.itemID ?? "")) ? 2 : 0)
            )
            .shadow(
                color: isDragging ? CiderColors.shadowMedium : CiderColors.shadowLight,
                radius: isDragging ? 12 : 4,
                y: isDragging ? 6 : 2
            )
            .scaleEffect(isDragging ? 1.03 : 1.0)
            .animation(reduceMotion ? .none : .snappy(duration: 0.2), value: isDragging)
            // Offset applied AFTER animation so it doesn't get animated on drop
            .offset(dragOffset)
            .onHover { isHovered = $0 }
            .gesture(dragGesture)
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch node.itemType {
        case "bookmark":
            bookmarkCard
        case "note":
            noteCard
        case "todo":
            todoCard
        case "folderGroup":
            folderGroupPlaceholder
        default:
            unknownCard
        }
    }

    @ViewBuilder
    private var bookmarkCard: some View {
        if let itemID = node.itemID,
           let uuid = UUID(uuidString: itemID),
           let bookmark = viewModel.bookmarkLookup[uuid] {
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: .grid,
                cardSizing: CardSizing(scale: 1.0),
                onShowDetails: { viewModel.handleItemClicked(itemID: itemID, type: "bookmark") },
                onOpen: { viewModel.handleItemDoubleClicked(itemID: itemID, type: "bookmark") },
                onDelete: {},
                isSelected: viewModel.selectedItemIDs.contains(itemID)
            )
        } else {
            missingItemCard(type: "Bookmark")
        }
    }

    @ViewBuilder
    private var noteCard: some View {
        if let itemID = node.itemID,
           let uuid = UUID(uuidString: itemID),
           let note = viewModel.noteLookup[uuid] {
            NoteCardView(
                note: note,
                mode: .grid,
                cardSizing: NoteCardSizing(scale: 1.0),
                searchText: "",
                folders: [],
                onOpen: { viewModel.handleItemClicked(itemID: itemID, type: "note") },
                onRename: { _ in },
                onDelete: {},
                onMoveToFolder: { _ in },
                isSelected: viewModel.selectedItemIDs.contains(itemID)
            )
        } else {
            missingItemCard(type: "Note")
        }
    }

    @ViewBuilder
    private var todoCard: some View {
        if let itemID = node.itemID,
           let uuid = UUID(uuidString: itemID),
           let todo = viewModel.todoLookup[uuid] {
            TodoCardCardView(
                todoCard: todo,
                onOpen: { viewModel.handleItemClicked(itemID: itemID, type: "todo") },
                isSelected: viewModel.selectedItemIDs.contains(itemID)
            )
        } else {
            missingItemCard(type: "Todo")
        }
    }

    @ViewBuilder
    private var folderGroupPlaceholder: some View {
        CanvasFolderGroupView(
            node: node,
            zoom: zoom,
            viewModel: viewModel
        )
    }

    @ViewBuilder
    private func missingItemCard(type: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "questionmark.square.dashed")
                .font(CiderFont.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(CiderColors.tertiary)
            Text("\(type) removed")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(width: node.size.width, height: 80)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    @ViewBuilder
    private var unknownCard: some View {
        Text(node.itemType)
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
            .frame(width: node.size.width, height: 60)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                // Global coordinate space gives screen-space translation.
                // Divide by zoom to get canvas-space offset.
                dragOffset = CGSize(
                    width: value.translation.width / zoom,
                    height: value.translation.height / zoom
                )
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: node.position.x + value.translation.width / zoom,
                    y: node.position.y + value.translation.height / zoom
                )
                // Update position and clear offset in the same transaction
                // with no animation, so there's no intermediate frame.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.moveNode(id: node.id, to: newPosition)
                    dragOffset = .zero
                }
                // Animate the shadow/scale change separately
                isDragging = false
            }
    }

    // MARK: - Helpers

}
