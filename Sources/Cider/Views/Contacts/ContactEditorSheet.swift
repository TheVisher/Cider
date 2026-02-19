import SwiftUI

struct ContactEditorSheet: View {
    let existingContact: ContactCard?
    let onSave: (String, String, Date?, String, [UUID], Bool) -> Void
    let onDelete: ((ContactCard) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var displayName: String
    @State private var relationshipLabel: String
    @State private var notes: String
    @State private var selectedLabelIDs: Set<UUID>
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var addBirthdayDateCard: Bool
    @State private var draftLabelName = ""

    init(
        existingContact: ContactCard?,
        onSave: @escaping (String, String, Date?, String, [UUID], Bool) -> Void,
        onDelete: ((ContactCard) -> Void)? = nil
    ) {
        self.existingContact = existingContact
        self.onSave = onSave
        self.onDelete = onDelete

        _displayName = State(initialValue: existingContact?.displayName ?? "")
        _relationshipLabel = State(initialValue: existingContact?.relationshipLabel ?? "")
        _notes = State(initialValue: existingContact?.notes ?? "")
        _selectedLabelIDs = State(initialValue: Set(existingContact?.labelIDs ?? []))
        _hasBirthday = State(initialValue: existingContact?.birthday != nil)
        _birthday = State(initialValue: existingContact?.birthday ?? Date())
        _addBirthdayDateCard = State(initialValue: existingContact?.birthday == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(existingContact == nil ? "New Contact Card" : "Edit Contact Card")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.primary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                TextField("Relationship", text: $relationshipLabel)
                    .textFieldStyle(.roundedBorder)

                Toggle("Has Birthday", isOn: $hasBirthday)
                    .toggleStyle(.switch)

                if hasBirthday {
                    DatePicker(
                        "Birthday",
                        selection: $birthday,
                        displayedComponents: [.date]
                    )

                    Toggle("Create/Update Birthday Date Card", isOn: $addBirthdayDateCard)
                        .toggleStyle(.switch)
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

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
                if let existingContact {
                    Button("Delete", role: .destructive) {
                        onDelete?(existingContact)
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
                        displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        relationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        hasBirthday ? birthday : nil,
                        notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        Array(selectedLabelIDs),
                        hasBirthday && addBirthdayDateCard
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 440, maxWidth: 600)
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
}
