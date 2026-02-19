import SwiftUI

struct DateCardEditorSheet: View {
    let existingCard: DateCard?
    let defaultDate: Date
    let onSave: (String, String, Date, Date?, Bool, String, Double?, [UUID]) -> Void
    let onDelete: ((DateCard) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var title: String
    @State private var details: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var allDay: Bool
    @State private var hasEndDate: Bool
    @State private var location: String
    @State private var amountText: String
    @State private var selectedLabelIDs: Set<UUID>
    @State private var draftLabelName = ""

    init(
        existingCard: DateCard?,
        defaultDate: Date,
        onSave: @escaping (String, String, Date, Date?, Bool, String, Double?, [UUID]) -> Void,
        onDelete: ((DateCard) -> Void)? = nil
    ) {
        self.existingCard = existingCard
        self.defaultDate = defaultDate
        self.onSave = onSave
        self.onDelete = onDelete

        let baseStart = existingCard?.startAt ?? defaultDate
        let baseEnd = existingCard?.endAt ?? Calendar.current.date(byAdding: .hour, value: 1, to: baseStart) ?? baseStart

        _title = State(initialValue: existingCard?.title ?? "")
        _details = State(initialValue: existingCard?.details ?? "")
        _startAt = State(initialValue: baseStart)
        _endAt = State(initialValue: baseEnd)
        _allDay = State(initialValue: existingCard?.allDay ?? false)
        _hasEndDate = State(initialValue: existingCard?.endAt != nil)
        _location = State(initialValue: existingCard?.location ?? "")
        _amountText = State(initialValue: existingCard?.amount.map { Self.currencyFormatter.string(from: NSNumber(value: $0)) ?? "\($0)" } ?? "")
        _selectedLabelIDs = State(initialValue: Set(existingCard?.labelIDs ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(existingCard == nil ? "New Date Card" : "Edit Date Card")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.primary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextField("Details", text: $details, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Toggle("All Day", isOn: $allDay)
                    .toggleStyle(.switch)

                DatePicker(
                    "Start",
                    selection: $startAt,
                    displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                )

                Toggle("Include End Time", isOn: $hasEndDate)
                    .toggleStyle(.switch)

                if hasEndDate {
                    DatePicker(
                        "End",
                        selection: $endAt,
                        displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                TextField("Location", text: $location)
                    .textFieldStyle(.roundedBorder)

                TextField("Amount (optional)", text: $amountText)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Labels")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    if labelStorage.labels.isEmpty {
                        Text("No labels yet. Add one below.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.xs) {
                                ForEach(labelStorage.labels) { label in
                                    labelChip(label)
                                }
                            }
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        TextField("New label", text: $draftLabelName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let trimmed = draftLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let created = labelStorage.createLabel(name: trimmed)
                            selectedLabelIDs.insert(created.id)
                            draftLabelName = ""
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                if let existingCard {
                    Button("Delete", role: .destructive) {
                        onDelete?(existingCard)
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer(minLength: 0)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)

                Button("Save") {
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        details.trimmingCharacters(in: .whitespacesAndNewlines),
                        startAt,
                        hasEndDate ? endAt : nil,
                        allDay,
                        location.trimmingCharacters(in: .whitespacesAndNewlines),
                        parsedAmount,
                        Array(selectedLabelIDs)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 420, maxWidth: 560)
    }

    private func labelChip(_ label: CardLabel) -> some View {
        let isSelected = selectedLabelIDs.contains(label.id)
        return Button {
            if isSelected {
                selectedLabelIDs.remove(label.id)
            } else {
                selectedLabelIDs.insert(label.id)
            }
        } label: {
            Text(label.name)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private var parsedAmount: Double? {
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
