import SwiftUI

enum CalendarProjectionMode: String, CaseIterable {
    case week
    case month
}

struct CalendarProjectionView: View {
    let items: [LibraryItemV2]
    let mode: CalendarProjectionMode
    let anchorDate: Date
    let showsGhostCells: Bool
    var onSelectDay: ((Date) -> Void)? = nil
    var onSelectDateCard: ((DateCard) -> Void)? = nil

    private let calendar = Calendar.current

    private var days: [Date] {
        switch mode {
        case .week:
            return weekDays(around: anchorDate)
        case .month:
            return monthGridDays(containing: anchorDate)
        }
    }

    private var itemsByDay: [Date: [LibraryItemV2]] {
        var grouped: [Date: [LibraryItemV2]] = [:]
        for item in items {
            guard let anchor = item.dateAnchor else { continue }
            let day = calendar.startOfDay(for: anchor)
            grouped[day, default: []].append(item)
        }
        for day in grouped.keys {
            grouped[day]?.sort { lhs, rhs in
                let lhsDate = lhs.dateAnchor ?? lhs.createdDate
                let rhsDate = rhs.dateAnchor ?? rhs.createdDate
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return grouped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            weekdayHeader

            let columns = Array(repeating: GridItem(.flexible(minimum: 88), spacing: Spacing.xs), count: 7)
            LazyVGrid(columns: columns, spacing: Spacing.xs) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]

        return HStack(spacing: Spacing.xs) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let dayItems = itemsByDay[dayStart] ?? []
        let isToday = calendar.isDateInToday(dayStart)
        let isCurrentMonth = calendar.isDate(dayStart, equalTo: anchorDate, toGranularity: .month)

        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(dayNumberText(for: dayStart))
                .font(CiderFont.captionSemibold)
                .foregroundColor(isToday ? CiderColors.controlAccent : (isCurrentMonth ? CiderColors.secondary : CiderColors.quaternary))

            if dayItems.isEmpty {
                if showsGhostCells {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.separatorLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                .stroke(CiderColors.separator, lineWidth: CiderBorder.innerStrokeWidth)
                        )
                        .frame(height: 52)
                        .opacity(0.35)
                } else {
                    Spacer(minLength: 52)
                }
            } else {
                ForEach(Array(dayItems.prefix(3).enumerated()), id: \.offset) { _, item in
                    if case .dateCard(let dateCard) = item {
                        Button {
                            onSelectDateCard?(dateCard)
                        } label: {
                            Text(item.title)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.xxs)
                                .padding(.vertical, Spacing.hairline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                        .fill(CiderColors.surfaceSubtle)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(item.title)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, Spacing.hairline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                    .fill(CiderColors.surfaceSubtle)
                            )
                    }
                }

                if dayItems.count > 3 {
                    Text("+\(dayItems.count - 3) more")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isToday ? CiderColors.controlAccent.opacity(0.35) : CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if dayItems.isEmpty {
                onSelectDay?(dayStart)
            }
        }
    }

    private func weekDays(around date: Date) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    private func monthGridDays(containing date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start) else { return [] }
        let monthEnd = monthInterval.end.addingTimeInterval(-1)
        guard let lastWeek = calendar.dateInterval(of: .weekOfYear, for: monthEnd) else { return [] }

        let start = firstWeek.start
        let end = lastWeek.end
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func dayNumberText(for date: Date) -> String {
        let day = calendar.component(.day, from: date)
        return "\(day)"
    }
}
