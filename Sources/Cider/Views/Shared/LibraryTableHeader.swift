import SwiftUI

// MARK: - Table Header Bar

struct LibraryTableHeader: View {
    @Binding var columnConfig: TableColumnConfig
    var allSelected: Bool
    var onToggleSelectAll: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Checkbox column (fixed width)
            Button(action: onToggleSelectAll) {
                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                    .font(CiderFont.body)
                    .foregroundColor(allSelected ? CiderColors.controlAccent : CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .accessibilityLabel(allSelected ? "Deselect all" : "Select all")
            .help(allSelected ? "Deselect all" : "Select all")

            // Dynamic columns
            ForEach(columnConfig.visibleColumns, id: \.self) { column in
                TableHeaderCell(
                    column: column,
                    width: columnConfig.width(for: column),
                    isFlexible: column.isFlexible,
                    onResize: column.isFlexible ? nil : { newWidth in
                        columnConfig.setWidth(newWidth, for: column)
                    }
                )
            }

            // Column picker (fixed width)
            TableColumnPicker(columnConfig: $columnConfig)
                .frame(width: 40)
        }
        .frame(height: 32)
        .padding(.horizontal, Spacing.sm)
        .background(CiderColors.surfaceSubtle)
        .overlay(alignment: .bottom) {
            CiderColors.separator.frame(height: 0.5)
        }
    }
}

// MARK: - Single Header Cell

private struct TableHeaderCell: View {
    let column: TableColumnID
    let width: CGFloat
    let isFlexible: Bool
    var onResize: ((CGFloat) -> Void)?

    @State private var isResizing = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Text(column.displayName)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.sm)

            if let onResize {
                // Resize handle (only on fixed-width columns)
                Rectangle()
                    .fill(CiderColors.separator)
                    .frame(width: 1)
                    .padding(.vertical, Spacing.sm)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .cursor(.resizeLeftRight)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if !isResizing {
                                            isResizing = true
                                            dragStartX = value.startLocation.x
                                            dragStartWidth = width
                                        }
                                        let delta = value.location.x - dragStartX
                                        let newWidth = max(dragStartWidth + delta, TableColumnID.minWidth)
                                        onResize(newWidth)
                                    }
                                    .onEnded { _ in
                                        isResizing = false
                                    }
                            )
                    )
            }
        }
        .frame(width: isFlexible ? nil : width)
        .frame(maxWidth: isFlexible ? .infinity : nil)
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
                .frame(width: 28, height: 28)
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
            .frame(width: 160)
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
