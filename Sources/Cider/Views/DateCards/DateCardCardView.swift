import SwiftUI

struct DateCardCardView: View {
    let dateCard: DateCard
    var onOpen: (() -> Void)? = nil

    @State private var isHovered = false

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dateCard.startAt)
    }

    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: dateCard.startAt).uppercased()
    }

    private var timeString: String {
        if dateCard.allDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let endAt = dateCard.endAt {
            return "\(formatter.string(from: dateCard.startAt)) - \(formatter.string(from: endAt))"
        }
        return formatter.string(from: dateCard.startAt)
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(monthString)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)

                        Text(dayString)
                            .font(CiderFont.headingSemibold)
                            .foregroundColor(CiderColors.primary)
                    }

                    Spacer(minLength: 0)

                    if dateCard.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                }

                Text(dateCard.title)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                if !dateCard.details.isEmpty {
                    Text(dateCard.details)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "clock")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Text(timeString)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                if !dateCard.location.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                        Text(dateCard.location)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }

                if let amount = dateCard.amount {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "dollarsign.circle")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                        Text(Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
