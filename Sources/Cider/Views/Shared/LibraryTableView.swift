import SwiftUI

// MARK: - Library Table View (Self-contained with scroll)

/// Unified table list view for all LibraryItemV2 types.
/// Includes a sticky header above a scrollable row list.
/// Use this when the table owns its own scroll region (e.g., HomeDashboardView).
struct LibraryTableView: View {
    let items: [LibraryItemV2]
    let labels: [CardLabel]
    var folders: [Folder] = []
    @Binding var columnConfig: TableColumnConfig
    let selectedItemIDs: Set<String>
    var focusedItemID: String? = nil
    let onOpen: (LibraryItemV2) -> Void
    let onSelect: (LibraryItemV2) -> Void
    let onShiftSelect: (LibraryItemV2) -> Void
    var onSelectAll: (() -> Void)? = nil
    var onDeselectAll: (() -> Void)? = nil
    @Binding var scrollToItemID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allSelected: Bool {
        !items.isEmpty && items.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryTableHeader(
                columnConfig: $columnConfig,
                allSelected: allSelected,
                onToggleSelectAll: {
                    if allSelected {
                        onDeselectAll?()
                    } else {
                        onSelectAll?()
                    }
                }
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LibraryTableRows(
                        items: items,
                        labels: labels,
                        folders: folders,
                        columnConfig: columnConfig,
                        selectedItemIDs: selectedItemIDs,
                        focusedItemID: focusedItemID,
                        onOpen: onOpen,
                        onSelect: onSelect,
                        onShiftSelect: onShiftSelect
                    )
                }
                .scrollIndicators(.hidden)
                .onChange(of: scrollToItemID) { _, id in
                    if let id {
                        withAnimation(reduceMotion ? .none : .snappy) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        scrollToItemID = nil
                    }
                }
            }
        }
    }
}

// MARK: - Library Table Rows (No scroll, embeddable)

/// Just the rows — use inside an existing ScrollView.
/// Pair with a `LibraryTableHeader` above the scroll region.
struct LibraryTableRows: View {
    let items: [LibraryItemV2]
    let labels: [CardLabel]
    var folders: [Folder] = []
    let columnConfig: TableColumnConfig
    let selectedItemIDs: Set<String>
    var focusedItemID: String? = nil
    let onOpen: (LibraryItemV2) -> Void
    let onSelect: (LibraryItemV2) -> Void
    let onShiftSelect: (LibraryItemV2) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                LibraryTableRow(
                    item: item,
                    columnConfig: columnConfig,
                    labels: labels,
                    folders: folders,
                    isSelected: selectedItemIDs.contains(item.id),
                    isFocused: focusedItemID == item.id,
                    onOpen: { onOpen(item) },
                    onSelect: { onSelect(item) },
                    onShiftSelect: { onShiftSelect(item) }
                )
                .id(item.id)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
