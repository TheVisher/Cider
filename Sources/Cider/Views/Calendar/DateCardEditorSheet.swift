import SwiftUI

struct DateCardEditorSheet: View {
    let existingCard: DateCard?
    let defaultDate: Date
    let onSave: (String, String, Date, Date?, Bool, String, Double?, [UUID], DateCardRecurrenceRule?, [SurfacingRule]) -> Void
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
    @State private var hasRecurrence: Bool
    @State private var recurrenceFrequency: DateCardRecurrenceFrequency
    @State private var recurrenceInterval: Int
    @State private var draftLabelName = ""
    @State private var customReminderEnabled: Bool
    @State private var reminderDays: Int
    @State private var notificationEnabled: Bool
    @State private var notificationMinutes: Int

    init(
        existingCard: DateCard?,
        defaultDate: Date,
        onSave: @escaping (String, String, Date, Date?, Bool, String, Double?, [UUID], DateCardRecurrenceRule?, [SurfacingRule]) -> Void,
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
        _hasRecurrence = State(initialValue: existingCard?.recurrenceRule != nil)
        _recurrenceFrequency = State(initialValue: existingCard?.recurrenceRule?.frequency ?? .weekly)
        _recurrenceInterval = State(initialValue: existingCard?.recurrenceRule?.interval ?? 1)

        let existingReminderRule = existingCard?.rules.first(where: { $0.type == .surfaceDaysBeforeDate && $0.isEnabled })
        _customReminderEnabled = State(initialValue: existingReminderRule != nil)
        _reminderDays = State(initialValue: existingReminderRule?.integerValue ?? 7)

        let existingNotificationRule = existingCard?.rules.first(where: { $0.type == .remindBeforeMinutes && $0.isEnabled })
        _notificationEnabled = State(initialValue: existingNotificationRule != nil)
        _notificationMinutes = State(initialValue: existingNotificationRule?.integerValue ?? 30)
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

                Toggle("Repeat", isOn: $hasRecurrence)
                    .toggleStyle(.switch)

                if hasRecurrence {
                    HStack(spacing: Spacing.sm) {
                        Text("Every")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                        TextField("", value: $recurrenceInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Picker("", selection: $recurrenceFrequency) {
                            Text("Day(s)").tag(DateCardRecurrenceFrequency.daily)
                            Text("Week(s)").tag(DateCardRecurrenceFrequency.weekly)
                            Text("Month(s)").tag(DateCardRecurrenceFrequency.monthly)
                            Text("Year(s)").tag(DateCardRecurrenceFrequency.yearly)
                        }
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Reminders")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    Toggle("Custom reminder window", isOn: $customReminderEnabled)
                        .toggleStyle(.switch)

                    if customReminderEnabled {
                        HStack(spacing: Spacing.sm) {
                            Text("Surface")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.secondary)
                            Stepper(value: $reminderDays, in: 1...30) {
                                Text("\(reminderDays) day\(reminderDays == 1 ? "" : "s") before")
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.secondary)
                            }
                        }
                    }

                    Toggle("System notification", isOn: $notificationEnabled)
                        .toggleStyle(.switch)

                    if notificationEnabled {
                        Picker("Notify before", selection: $notificationMinutes) {
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("1 day").tag(1440)
                        }
                    }
                }

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
                    let rule: DateCardRecurrenceRule? = hasRecurrence
                        ? DateCardRecurrenceRule(frequency: recurrenceFrequency, interval: max(recurrenceInterval, 1))
                        : nil
                    var surfacingRules: [SurfacingRule] = []
                    if customReminderEnabled {
                        surfacingRules.append(SurfacingRule(type: .surfaceDaysBeforeDate, integerValue: reminderDays))
                    }
                    if notificationEnabled {
                        surfacingRules.append(SurfacingRule(type: .remindBeforeMinutes, integerValue: notificationMinutes))
                    }
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        details.trimmingCharacters(in: .whitespacesAndNewlines),
                        startAt,
                        hasEndDate ? endAt : nil,
                        allDay,
                        location.trimmingCharacters(in: .whitespacesAndNewlines),
                        parsedAmount,
                        Array(selectedLabelIDs),
                        rule,
                        surfacingRules
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
