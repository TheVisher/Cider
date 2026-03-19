import SwiftUI

// MARK: - Table Header Bar

struct LibraryTableHeader: View {
    @Binding var columnConfig: TableColumnConfig
    var allSelected: Bool
    var onToggleSelectAll: () -> Void

    private var visibleColumns: [TableColumnID] {
        columnConfig.visibleColumns
    }

    var body: some View {
        HStack(spacing: 0) {
            // Checkbox column (fixed width)
            Button(action: onToggleSelectAll) {
                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                    .font(CiderFont.body)
                    .foregroundColor(allSelected ? CiderColors.controlAccent : CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: LibraryTableDesign.checkboxColumnWidth)
            .accessibilityLabel(allSelected ? "Deselect all" : "Select all")
            .help(allSelected ? "Deselect all" : "Select all")

            // Dynamic columns with resize handles between them
            ForEach(Array(visibleColumns.enumerated()), id: \.element) { index, column in
                // Column label
                Text(column.displayName)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: column.isFlexible ? .infinity : nil, alignment: .leading)
                    .frame(width: column.isFlexible ? nil : columnConfig.width(for: column))
                    .padding(.leading, Spacing.sm)

                // Resize handle between this column and the next
                // (skip after the last column)
                if index < visibleColumns.count - 1 {
                    let leftColumn = column
                    let rightColumn = visibleColumns[index + 1]
                    ColumnResizeHandle(
                        leftColumn: leftColumn,
                        rightColumn: rightColumn,
                        leftWidth: columnConfig.width(for: leftColumn),
                        rightWidth: columnConfig.width(for: rightColumn),
                        leftIsFlexible: leftColumn.isFlexible,
                        rightIsFlexible: rightColumn.isFlexible,
                        onResize: { newLeftWidth, newRightWidth in
                            if !leftColumn.isFlexible {
                                columnConfig.setWidth(newLeftWidth, for: leftColumn)
                            }
                            if !rightColumn.isFlexible {
                                columnConfig.setWidth(newRightWidth, for: rightColumn)
                            }
                        }
                    )
                }
            }

            // Column picker (fixed width)
            TableColumnPicker(columnConfig: $columnConfig)
                .frame(width: LibraryTableDesign.menuColumnWidth)
        }
        .frame(height: LibraryTableDesign.headerHeight)
        .padding(.horizontal, Spacing.sm)
        .background(CiderColors.surfaceSubtle)
        .overlay(alignment: .bottom) {
            CiderColors.separator.frame(height: CiderBorder.hairlineStrokeWidth)
        }
    }

}

// MARK: - Resize Handle Between Two Columns

private struct ColumnResizeHandle: View {
    let leftColumn: TableColumnID
    let rightColumn: TableColumnID
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let leftIsFlexible: Bool
    let rightIsFlexible: Bool
    let onResize: (_ newLeftWidth: CGFloat, _ newRightWidth: CGFloat) -> Void

    @State private var isResizing = false
    @State private var dragStartLeftWidth: CGFloat = 0
    @State private var dragStartRightWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CiderColors.separator)
            .frame(width: LibraryTableDesign.columnSeparatorWidth)
            .padding(.vertical, Spacing.sm)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: LibraryTableDesign.columnDragHitWidth)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    dragStartLeftWidth = leftWidth
                                    dragStartRightWidth = rightWidth
                                }
                                let delta = value.translation.width
                                let minW = TableColumnID.minWidth

                                if leftIsFlexible {
                                    // Left is flexible — only resize right column.
                                    // Drag right = right grows, drag left = right shrinks.
                                    // (Inverted: handle moves right means right column's
                                    //  left edge moves right, so it shrinks)
                                    let newRight = max(dragStartRightWidth - delta, minW)
                                    onResize(0, newRight)
                                } else if rightIsFlexible {
                                    // Right is flexible — only resize left column.
                                    let newLeft = max(dragStartLeftWidth + delta, minW)
                                    onResize(newLeft, 0)
                                } else {
                                    // Both fixed — redistribute space between them.
                                    let maxGrow = dragStartRightWidth - minW
                                    let maxShrink = dragStartLeftWidth - minW
                                    let clampedDelta = min(max(delta, -maxShrink), maxGrow)
                                    onResize(
                                        dragStartLeftWidth + clampedDelta,
                                        dragStartRightWidth - clampedDelta
                                    )
                                }
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
            )
    }
}

// MARK: - Column Visibility Picker

private struct TableColumnPicker: View {
    @Binding var columnConfig: TableColumnConfig

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            Image(systemName: "plus")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle columns")
        .help("Toggle columns")
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Columns")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)

                ForEach(TableColumnID.allCases, id: \.self) { column in
                    Button {
                        columnConfig.toggleVisibility(of: column)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: columnConfig.hiddenColumns.contains(column) ? "square" : "checkmark.square.fill")
                                .foregroundColor(column.canHide ? CiderColors.controlAccent : CiderColors.quaternary)
                            Text(column.displayName)
                                .font(CiderFont.body)
                                .foregroundColor(column.canHide ? CiderColors.primary : CiderColors.quaternary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!column.canHide)
                }
            }
            .padding(.bottom, Spacing.sm)
            .frame(width: LibraryTableDesign.columnPickerPopoverWidth)
        }
    }
}

// MARK: - Cursor Modifier

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
