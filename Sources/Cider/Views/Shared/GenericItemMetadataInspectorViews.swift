import SwiftUI

extension LibraryEntityRef {
    static func dateCard(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .dateCard, entityID: id)
    }

    static func todo(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .todo, entityID: id)
    }

    static func vaultFile(_ id: UUID) -> LibraryEntityRef {
        LibraryEntityRef(type: .vaultFile, entityID: id)
    }
}

struct BasicItemMetadataInspectorView: View {
    let title: String
    let typeLabel: String
    let createdAt: Date
    let updatedAt: Date
    var folderName: String?
    var labelIDs: [UUID] = []
    var linkedRef: LibraryEntityRef
    var extraRows: [ItemMetadataRow] = []
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var isLinkedExpanded = true
    @State private var isFolderExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isInfoExpanded = true

    var body: some View {
        ItemMetadataInspectorView {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .padding(.bottom, Spacing.md)

            sectionDivider

            ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
                let rows = relatedRows
                if rows.isEmpty {
                    Text("No linked items.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                } else {
                    ItemMetadataRowsView(
                        rows: rows,
                        onOpenRef: onOpenLinkedRef,
                        canOpenRef: canOpenLinkedRef
                    )
                }
            }

            if let folderName = trimmedFolderName {
                sectionDivider

                ItemMetadataSectionView(title: "Folder", isExpanded: $isFolderExpanded) {
                    ItemMetadataRowsView(rows: [
                        ItemMetadataRow(id: "folder", symbol: "folder", title: folderName)
                    ])
                }
            }

            let labelRows = labelRows
            if !labelRows.isEmpty {
                sectionDivider

                ItemMetadataSectionView(title: "Labels", isExpanded: $isLabelsExpanded) {
                    ItemMetadataRowsView(rows: labelRows)
                }
            }

            if !extraRows.isEmpty {
                sectionDivider

                ItemMetadataSectionView(title: "Details", isExpanded: $isDetailsExpanded) {
                    ItemMetadataRowsView(rows: extraRows)
                }
            }

            sectionDivider

            ItemMetadataSectionView(title: "Info", isExpanded: $isInfoExpanded) {
                ItemMetadataRowsView(rows: ItemMetadataInfoRows.rows(
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    typeLabel: typeLabel
                ))
            }
        }
    }

    private var sectionDivider: some View {
        Divider().background(CiderColors.separator)
    }

    private var trimmedFolderName: String? {
        guard let folderName else { return nil }
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var labelRows: [ItemMetadataRow] {
        labelIDs.compactMap { id in
            guard let label = labelStorage.labels.first(where: { $0.id == id }) else { return nil }
            return ItemMetadataRow(id: "label-\(label.id.uuidString)", symbol: "tag", title: label.name)
        }
    }

    private var relatedRows: [ItemMetadataRow] {
        let refs = (try? ItemLinkService.shared.relatedRefs(for: linkedRef)) ?? []
        return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
    }
}

extension BasicItemMetadataInspectorView {
    init(
        dateCard: DateCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: dateCard.title,
            typeLabel: "Date Card",
            createdAt: dateCard.createdAt,
            updatedAt: dateCard.updatedAt,
            folderName: Self.folderName(for: dateCard.folderID),
            labelIDs: dateCard.labelIDs,
            linkedRef: .dateCard(dateCard.id),
            extraRows: DateCardMetadataRows.rows(for: dateCard),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    init(
        todo: TodoCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: todo.title,
            typeLabel: "Todo",
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt,
            folderName: Self.folderName(for: todo.folderID),
            labelIDs: todo.labelIDs,
            linkedRef: .todo(todo.id),
            extraRows: TodoMetadataRows.rows(for: todo),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    init(
        file: VaultFile,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil
    ) {
        self.init(
            title: file.displayTitle,
            typeLabel: "File",
            createdAt: file.createdAt,
            updatedAt: file.modifiedAt,
            folderName: Self.folderName(for: file.folderID),
            labelIDs: file.labelIDs,
            linkedRef: .vaultFile(file.id),
            extraRows: Self.fileRows(for: file),
            onOpenLinkedRef: onOpenLinkedRef,
            canOpenLinkedRef: canOpenLinkedRef
        )
    }

    private static func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name
    }

    private static func fileRows(for file: VaultFile) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(id: "kind", symbol: file.fileType.systemImageName, title: "Kind", value: file.fileType.displayName)
        ]

        let fileExtension = (file.filename as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileExtension.isEmpty {
            rows.append(ItemMetadataRow(id: "file-type", symbol: "doc", title: "File Type", value: fileExtension.uppercased()))
        }

        rows.append(ItemMetadataRow(id: "size", symbol: "externaldrive", title: "Size", value: ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)))

        return rows
    }
}

enum DateCardMetadataRows {
    static func rows(for dateCard: DateCard) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(id: "date", symbol: "calendar", title: "Date", value: dateValue(for: dateCard)),
            ItemMetadataRow(id: "time", symbol: "clock", title: "Time", value: timeValue(for: dateCard))
        ]

        let location = dateCard.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty {
            rows.append(ItemMetadataRow(id: "location", symbol: "mappin.and.ellipse", title: "Location", value: location))
        }

        if let amount = dateCard.amount {
            rows.append(ItemMetadataRow(id: "amount", symbol: "dollarsign.circle", title: "Amount", value: currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)))
        }

        return rows
    }

    private static func dateValue(for dateCard: DateCard) -> String {
        guard let endAt = dateCard.endAt,
              !Calendar.current.isDate(dateCard.startAt, inSameDayAs: endAt) else {
            return dateFormatter.string(from: dateCard.startAt)
        }

        return "\(dateFormatter.string(from: dateCard.startAt)) - \(dateFormatter.string(from: endAt))"
    }

    private static func timeValue(for dateCard: DateCard) -> String {
        if dateCard.allDay {
            return "All day"
        }

        let start = timeFormatter.string(from: dateCard.startAt)
        guard let endAt = dateCard.endAt else {
            return start
        }

        return "\(start) - \(timeFormatter.string(from: endAt))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

enum TodoMetadataRows {
    static func rows(for todo: TodoCard) -> [ItemMetadataRow] {
        var rows = [
            ItemMetadataRow(
                id: "status",
                symbol: todo.isCompleted ? "checkmark.circle.fill" : "circle",
                title: "Status",
                value: todo.isCompleted ? "Completed" : "Open"
            )
        ]

        if let dueDate = todo.dueDate {
            rows.append(ItemMetadataRow(id: "due", symbol: "calendar", title: "Due", value: dateFormatter.string(from: dueDate)))
        }

        if let priority = todo.priority {
            rows.append(ItemMetadataRow(id: "priority", symbol: priority.icon, title: "Priority", value: priority.displayName))
        }

        return rows
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
