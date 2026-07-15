import SwiftUI

struct DateCardDetailView: View {
    let dateCard: DateCard
    var onEdit: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var isMetadataExpanded = true
    @State private var isCompleted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared

    init(dateCard: DateCard, onEdit: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.dateCard = dateCard
        self.onEdit = onEdit
        self.onDismiss = onDismiss
        _isCompleted = State(initialValue: dateCard.isCompleted)
    }

    private var timeString: String {
        if dateCard.allDay { return "All Day" }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        if let end = dateCard.endAt {
            return "\(fmt.string(from: dateCard.startAt)) – \(fmt.string(from: end))"
        }
        return fmt.string(from: dateCard.startAt)
    }

    private var recurrenceString: String? {
        guard let rule = dateCard.recurrenceRule else { return nil }
        switch rule.frequency {
        case .daily:   return rule.interval == 1 ? "Daily" : "Every \(rule.interval) days"
        case .weekly:  return rule.interval == 1 ? "Weekly" : "Every \(rule.interval) weeks"
        case .monthly: return rule.interval == 1 ? "Monthly" : "Every \(rule.interval) months"
        case .yearly:  return rule.interval == 1 ? "Yearly" : "Every \(rule.interval) years"
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header: date + title
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(dateCard.startAt.formatted(.dateTime.month(.abbreviated)))
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(dateCard.startAt.formatted(.dateTime.day()))
                        .font(CiderFont.headingSemibold)
                        .foregroundColor(CiderColors.primary)
                }
                .frame(width: 36, alignment: .leading)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(dateCard.title)
                        .font(CiderFont.subheading)
                        .foregroundColor(CiderColors.primary)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                        Text(timeString)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    if let url = dateCard.actionURL {
                        Button {
                            CiderOpenPolicy.shared.openIfAllowed(.untrustedWeb(url))
                        } label: {
                            Label("Open Link", systemImage: "link")
                                .font(CiderFont.bodyMedium)
                        }
                        .buttonStyle(.link)
                        .help(dateCard.actionURLString ?? "Open action link")
                    }

                    if !dateCard.location.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(CiderFont.captionMedium)
                                .foregroundColor(CiderColors.tertiary)
                            Text(dateCard.location)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Divider()

            // Details text
            if !dateCard.details.isEmpty {
                Text(dateCard.details)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Expandable metadata
            let hasMetadata = dateCard.amount != nil
                || dateCard.actionURLString != nil
                || recurrenceString != nil
                || !dateCard.labelIDs.isEmpty
                || dateCard.linkedEntities.contains(where: { $0.type == .contact })

            if hasMetadata {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) { isMetadataExpanded.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text("Details")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                        Spacer(minLength: 0)
                        Image(systemName: isMetadataExpanded ? "chevron.up" : "chevron.down")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isMetadataExpanded {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let actionURLString = dateCard.actionURLString {
                            detailRow(icon: "link", text: actionURLString)
                        }

                        if let amount = dateCard.amount {
                            let amountStr = Self.currencyFormatter.string(from: NSNumber(value: amount))
                                ?? String(format: "%.2f", amount)
                            detailRow(icon: "dollarsign.circle", text: amountStr)
                        }

                        if let recurrence = recurrenceString {
                            detailRow(icon: "repeat", text: recurrence)
                        }

                        let labels = labelStorage.labels.filter { dateCard.labelIDs.contains($0.id) }
                        if !labels.isEmpty {
                            detailRow(icon: "tag", text: labels.map(\.name).joined(separator: ", "))
                        }

                        ForEach(dateCard.linkedEntities.filter({ $0.type == .contact })) { ref in
                            if let contact = contactStorage.contact(for: ref.entityID) {
                                detailRow(icon: "person.crop.circle", text: contact.displayName)
                            }
                        }
                    }
                }
            }

            Divider()

            // Mark as completed toggle
            Button {
                isCompleted.toggle()
                _ = DateCardStorage.shared.markCompleted(dateCard.id, completed: isCompleted)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(isCompleted ? CiderColors.controlAccent : CiderColors.tertiary)
                    Text("Mark as completed")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                Button("Edit") {
                    onEdit?()
                }
                .buttonStyle(.borderless)
                .foregroundColor(CiderColors.secondary)

                Button("Done") {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 14)
            Text(text)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(2)
        }
    }
}
