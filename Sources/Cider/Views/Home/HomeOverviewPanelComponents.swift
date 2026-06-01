import SwiftUI

struct HomeOverviewPanel<Content: View>: View {
    let title: String
    var minHeight: CGFloat? = nil
    var fixedHeight: CGFloat? = nil
    var headerAccessory: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if let fixedHeight {
                panelBody
                    .frame(maxWidth: .infinity)
                    .frame(height: fixedHeight, alignment: .topLeading)
            } else {
                panelBody
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(CiderColors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(CiderColors.borderDefault, lineWidth: 1)
            )
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(title.uppercased())
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .tracking(2)

                Spacer(minLength: Spacing.sm)

                if let headerAccessory {
                    headerAccessory
                }
            }

            content()

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
    }
}

struct HomeOverviewMetricBlock: View {
    let title: String
    let value: Int
    var minHeight: CGFloat = HomeOverviewDesign.attentionMetricTileHeight

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(value)")
                .font(CiderFont.displaySemibold)
                .foregroundColor(CiderColors.primary)
            Text(title.uppercased())
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.6)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceInput)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

struct HomeOverviewDayChip: View {
    let date: Date
    let isSelected: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(CiderFont.captionSemibold)
                .foregroundColor(isSelected ? Color.black.opacity(0.65) : CiderColors.tertiary)
            Text(date.formatted(.dateTime.day()))
                .font(CiderFont.displaySemibold)
                .foregroundColor(isSelected ? Color.black.opacity(0.78) : CiderColors.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color(red: 0.93, green: 0.87, blue: 0.76)) : AnyShapeStyle(CiderColors.surfaceInput))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(isSelected ? CiderColors.borderHover : CiderColors.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityLabel(Text(calendar.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted)))
    }
}

struct HomeOverviewTimelineRow: View {
    let item: LibraryItemV2
    let subtitle: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(CiderColors.borderSubtle)
                        .frame(width: 1)
                        .padding(.top, 3)

                    Circle()
                        .fill(item.dashboardAccentColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(CiderColors.surfaceElevated, lineWidth: 2)
                        )
                        .padding(.top, 6)
                }
                .frame(width: 14)
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.dashboardActivityTitle)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(subtitle)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)

                        Spacer(minLength: Spacing.sm)

                        Text(item.updatedDate.formatted(.relative(presentation: .named)))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

struct HomeOverviewCaptureTimeline: View {
    let items: [LibraryItemV2]
    let onOpen: (LibraryItemV2) -> Void

    private var visibleItems: [LibraryItemV2] {
        Array(items.prefix(6))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(visibleItems, id: \.id) { item in
                HomeOverviewCaptureTimelineNode(
                    item: item,
                    onOpen: {
                        onOpen(item)
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: HomeOverviewCaptureTimelineLayout.totalHeight,
            maxHeight: HomeOverviewCaptureTimelineLayout.totalHeight
        )
        .padding(.top, Spacing.xs)
    }
}

private enum HomeOverviewCaptureTimelineLayout {
    static let railTop: CGFloat = 52
    static let nodeSize: CGFloat = 28
    static let railHeight: CGFloat = 2
    static let totalHeight: CGFloat = 194
}

private struct HomeOverviewCaptureTimelineNode: View {
    let item: LibraryItemV2
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                Text(item.createdDate.formatted(.dateTime.hour().minute()))
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(CiderColors.borderSubtle, lineWidth: 1)
                            )
                    )
                    .frame(height: HomeOverviewCaptureTimelineLayout.railTop, alignment: .top)

                HStack(spacing: Spacing.xs) {
                    Rectangle()
                        .fill(item.dashboardAccentColor.opacity(0.65))
                        .frame(height: HomeOverviewCaptureTimelineLayout.railHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(item.dashboardAccentColor.opacity(0.18))
                                .frame(height: 6)
                                .blur(radius: 6)
                        }
                        .padding(.leading, Spacing.sm)

                    nodeIcon

                    Rectangle()
                        .fill(item.dashboardAccentColor.opacity(0.22))
                        .frame(height: HomeOverviewCaptureTimelineLayout.railHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(item.dashboardAccentColor.opacity(0.08))
                                .frame(height: 6)
                                .blur(radius: 6)
                        }
                        .padding(.trailing, Spacing.sm)
                }

                label
                    .padding(.top, Spacing.sm)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: HomeOverviewCaptureTimelineLayout.totalHeight,
                maxHeight: HomeOverviewCaptureTimelineLayout.totalHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nodeIcon: some View {
        ZStack {
            Circle()
                .fill(item.dashboardAccentColor.opacity(0.18))
                .frame(
                    width: HomeOverviewCaptureTimelineLayout.nodeSize,
                    height: HomeOverviewCaptureTimelineLayout.nodeSize
                )

            Circle()
                .fill(CiderColors.surfaceInput)
                .frame(width: 22, height: 22)

            Image(systemName: item.dashboardSymbol)
                .font(CiderFont.captionSemibold)
                .foregroundColor(item.dashboardAccentColor)
        }
            .frame(
                width: HomeOverviewCaptureTimelineLayout.nodeSize,
                height: HomeOverviewCaptureTimelineLayout.nodeSize
            )
    }

    private var label: some View {
        VStack(alignment: .center, spacing: Spacing.xxs) {
            Text(item.dashboardActivityTitle)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(item.dashboardSubtitle)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(item.createdDate.formatted(.relative(presentation: .named)))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 164)
    }
}

struct HomeOverviewAgendaRow: View {
    let item: LibraryItemV2
    let isNow: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Text(isNow ? "NOW" : item.dashboardTimeLabel)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(isNow ? item.dashboardAccentColor : CiderColors.tertiary)
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.title)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                    Text(item.dashboardSubtitle)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                Circle()
                    .fill(isNow ? AnyShapeStyle(item.dashboardAccentColor) : AnyShapeStyle(CiderColors.quaternary))
                    .frame(width: 8, height: 8)
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}

struct HomeOverviewTodoRow: View {
    enum Mode {
        case open
        case completed
    }

    let todo: TodoCard
    let mode: Mode
    let onToggleComplete: () -> Void
    let onOpen: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button(action: onToggleComplete) {
                Image(systemName: mode == .completed ? "checkmark.circle.fill" : "circle")
                    .font(CiderFont.headingMedium)
                    .foregroundColor(statusColor)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(mode == .completed ? "Mark incomplete" : "Mark complete")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(todo.title)
                            .font(CiderFont.labelMedium)
                            .foregroundColor(mode == .completed ? CiderColors.tertiary : CiderColors.primary)
                            .lineLimit(1)
                            .strikethrough(mode == .completed)

                        if let priority = todo.priority {
                            Image(systemName: priority.icon)
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(priority.color)
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(statusLabel)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(statusColor)
                            .lineLimit(1)

                        if todo.totalCount > 0 {
                            Text("\(todo.completedCount)/\(todo.totalCount)")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }

                        if !todo.details.isEmpty {
                            Text(todo.details)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xs)
    }

    private var statusColor: Color {
        if mode == .completed { return CiderColors.success }
        if let dueDate = todo.earliestApproachingDate {
            if dueDate < calendar.startOfDay(for: Date()) { return CiderColors.destructive }
            if calendar.isDateInToday(dueDate) { return CiderColors.success }
        }
        return todo.priority?.color ?? CiderColors.controlAccent
    }

    private var statusLabel: String {
        if mode == .completed {
            guard let completedAt = todo.completedAt else {
                return "Done"
            }
            if calendar.isDateInToday(completedAt) {
                return "Done today"
            }
            return "Done \(completedAt.formatted(.dateTime.month(.abbreviated).day()))"
        }

        guard let dueDate = todo.earliestApproachingDate else {
            return "No date"
        }

        if dueDate < calendar.startOfDay(for: Date()) {
            return "Overdue"
        }

        if calendar.isDateInToday(dueDate) {
            return todo.hasExplicitDueTime
                ? "Today \(dueDate.formatted(.dateTime.hour().minute()))"
                : "Today"
        }

        if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        }

        return dueDate.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct HomeOverviewResurfaceCard: View {
    let item: LibraryItemV2
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [item.dashboardAccentColor.opacity(0.4), CiderColors.surfaceHighlight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: HomeOverviewDesign.resurfaceCardHeight)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: item.dashboardSymbol)
                            .font(CiderFont.headingMedium)
                            .foregroundColor(CiderColors.textOnColor)
                            .padding(Spacing.sm)
                    }

                Text(item.entityType.rawValue.uppercased())
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .tracking(1.2)

                Text(item.title)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                Text(item.updatedDate.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(CiderColors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct HomeOverviewQuickActionButton: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(disabled ? CiderColors.quaternary : CiderColors.controlAccent)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(disabled ? CiderColors.secondary : CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                if let detail {
                    Text(detail)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: HomeOverviewDesign.quickActionButtonHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(CiderColors.borderSubtle, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct HomeOverviewEmptyStateCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)

            Text(subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.surfaceInput)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

extension LibraryItemV2 {
    var dashboardSymbol: String {
        switch self {
        case .bookmark: "bookmark.fill"
        case .note: "note.text"
        case .dateCard: "calendar"
        case .contact: "person.crop.circle"
        case .todo: "checklist"
        case .vaultFile: "doc.text"
        }
    }

    var dashboardAccentColor: Color {
        switch self {
        case .bookmark: CiderColors.warning
        case .note: CiderColors.controlAccent
        case .dateCard: CiderColors.warning
        case .contact: CiderColors.accentText
        case .todo: CiderColors.success
        case .vaultFile: CiderColors.tertiary
        }
    }

    var dashboardSubtitle: String {
        switch self {
        case .bookmark(let bookmark):
            return bookmark.hostDisplay
        case .note(let note):
            return note.contentPreview.isEmpty ? "Note" : note.contentPreview
        case .dateCard(let dateCard):
            return dateCard.location.isEmpty ? "Upcoming event" : dateCard.location
        case .contact(let contact):
            return contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel
        case .todo(let todo):
            return todo.details.isEmpty ? "Todo" : todo.details
        case .vaultFile(let file):
            return file.notes.isEmpty ? file.displayTitle : file.notes
        }
    }

    var dashboardActivityTitle: String {
        switch self {
        case .bookmark(let bookmark):
            return bookmark.title
        case .note(let note):
            return note.title
        case .dateCard(let dateCard):
            return dateCard.title
        case .contact(let contact):
            return contact.displayName
        case .todo(let todo):
            return todo.title
        case .vaultFile(let file):
            return file.displayTitle
        }
    }

    var dashboardTimeLabel: String {
        guard let date = dateAnchor else {
            return updatedDate.formatted(.dateTime.hour().minute())
        }

        return date.formatted(.dateTime.hour().minute())
    }
}
