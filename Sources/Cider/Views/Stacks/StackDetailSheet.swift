import SwiftUI

struct StackDetailSheet: View {
    let surface: StackSurfaceResult
    var onOpenBookmark: ((Bookmark) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil
    var onOpenDateCard: ((DateCard) -> Void)? = nil
    var onOpenContact: ((ContactCard) -> Void)? = nil
    var onOpenTodo: ((TodoCard) -> Void)? = nil
    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hiddenItemIDs: Set<String> = []

    private var visibleItems: [LibraryItemV2] {
        surface.items
            .compactMap { resolvedItem($0) }
            .filter { !hiddenItemIDs.contains($0.id) }
    }

    private var billsSummary: BillsSummary? {
        guard surface.stack.summaryModule == .bills else { return nil }
        let dateCards = visibleItems.compactMap { item -> DateCard? in
            if case .dateCard(let dateCard) = item {
                return dateCard
            }
            return nil
        }
        guard !dateCards.isEmpty else { return nil }

        let total = dateCards.compactMap(\.amount).reduce(0, +)
        let paid = dateCards.filter(\.isCompleted).compactMap(\.amount).reduce(0, +)
        let paidCount = dateCards.filter(\.isCompleted).count
        return BillsSummary(
            count: dateCards.count,
            paidCount: paidCount,
            total: total,
            paid: paid
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.stack.3d.up")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)

                Text(surface.stack.name)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("\(visibleItems.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }

            if let billsSummary {
                billsSummaryPanel(billsSummary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    if visibleItems.isEmpty {
                        EmptyStateView(
                            icon: "square.stack.3d.up",
                            title: "No visible stack items",
                            subtitle: "Items may be completed, filtered, or hidden in this sheet."
                        )
                    } else {
                        ForEach(visibleItems) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(Spacing.md)
        .frame(minWidth: 460, minHeight: 380)
    }

    private func icon(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark:
            "bookmark"
        case .note:
            "note.text"
        case .dateCard:
            "calendar"
        case .contact:
            "person.crop.circle"
        case .todo:
            "checklist"
        case .externalFile:
            "folder.badge.gear"
        case .vaultFile:
            "doc.on.doc"
        case .session:
            "rectangle.stack"
        }
    }

    private func resolvedItem(_ item: LibraryItemV2) -> LibraryItemV2? {
        if case .dateCard(let dateCard) = item {
            guard let latest = dateCardStorage.dateCard(for: dateCard.id) else { return nil }
            return .dateCard(latest)
        }
        return item
    }

    private func itemRow(_ item: LibraryItemV2) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon(for: item))
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 14)

                Text(item.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.xs)

                if case .dateCard(let dateCard) = item {
                    dateCardActions(dateCard)
                }

                Menu {
                    if case .dateCard(let dateCard) = item {
                        Button("Mark Done") {
                            setDateCardCompletion(dateCard.id, completed: true)
                        }
                        Button("Mark Incomplete") {
                            setDateCardCompletion(dateCard.id, completed: false)
                        }
                        Button("Snooze 1 Day") {
                            snooze(dateCard, days: 1)
                        }
                        Divider()
                    }
                    Button("Hide in This Sheet") {
                        hiddenItemIDs.insert(item.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Text(item.updatedDate.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dateCardActions(_ dateCard: DateCard) -> some View {
        Button(dateCard.isCompleted ? "Undo" : "Done") {
            setDateCardCompletion(dateCard.id, completed: !dateCard.isCompleted)
        }
        .buttonStyle(.borderless)
        .font(CiderFont.captionMedium)
        .foregroundColor(CiderColors.tertiary)
    }

    private func setDateCardCompletion(_ id: UUID, completed: Bool) {
        // Resolve latest card state from storage first to avoid stale toggle behavior.
        guard dateCardStorage.dateCard(for: id) != nil else { return }
        _ = dateCardStorage.markCompleted(id, completed: completed)
    }

    private func snooze(_ dateCard: DateCard, days: Int) {
        guard let shiftedStart = Calendar.current.date(byAdding: .day, value: days, to: dateCard.startAt) else { return }
        var updated = dateCard
        updated.startAt = shiftedStart
        if let endAt = dateCard.endAt,
           let shiftedEnd = Calendar.current.date(byAdding: .day, value: days, to: endAt) {
            updated.endAt = shiftedEnd
        }
        _ = dateCardStorage.updateDateCard(updated)
    }

    private func open(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark):
            onOpenBookmark?(bookmark)
        case .note(let note):
            onOpenNote?(note)
        case .dateCard(let dateCard):
            onOpenDateCard?(dateCard)
        case .contact(let contact):
            onOpenContact?(contact)
        case .todo(let todoCard):
            onOpenTodo?(todoCard)
        case .externalFile(let file):
            NotificationCenter.default.post(
                name: .openExternalFile,
                object: nil,
                userInfo: ["fileURL": file.path]
            )
        case .vaultFile:
            break
        case .session:
            // Sessions don't have an open callback in stacks yet
            break
        }
    }

    private func billsSummaryPanel(_ summary: BillsSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Bills Summary")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            HStack(spacing: Spacing.md) {
                summaryMetric(
                    title: "Total",
                    value: Self.currencyFormatter.string(from: NSNumber(value: summary.total)) ?? String(format: "%.2f", summary.total)
                )
                summaryMetric(
                    title: "Paid",
                    value: Self.currencyFormatter.string(from: NSNumber(value: summary.paid)) ?? String(format: "%.2f", summary.paid)
                )
                summaryMetric(
                    title: "Remaining",
                    value: Self.currencyFormatter.string(from: NSNumber(value: summary.remaining)) ?? String(format: "%.2f", summary.remaining)
                )
                summaryMetric(
                    title: "Completed",
                    value: "\(summary.paidCount)/\(summary.count)"
                )
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(title)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
            Text(value)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct BillsSummary {
        let count: Int
        let paidCount: Int
        let total: Double
        let paid: Double

        var remaining: Double {
            max(0, total - paid)
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
