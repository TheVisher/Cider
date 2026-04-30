import AppKit
import SwiftUI

struct ContactEditorSheet: View {
    let existingContact: ContactCard?
    /// Parameters: draftContactID, displayName, relationship, birthday, notes,
    ///             labelIDs, addBirthdayDateCard, email, phone, address, hasAvatar, customFields
    let onSave: (UUID, String, String, Date?, String, [UUID], Bool, String, String, String, Bool, [ContactCustomField]) -> Void
    let onDelete: ((ContactCard) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    private let draftContactID: UUID

    @State private var displayName: String
    @State private var relationshipLabel: String
    @State private var notes: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String
    @State private var selectedLabelIDs: Set<UUID>
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var addBirthdayDateCard: Bool
    @State private var hasAvatar: Bool
    @State private var avatarImage: NSImage?
    @State private var customFields: [ContactCustomField]
    @State private var draftLabelName = ""

    init(
        existingContact: ContactCard?,
        onSave: @escaping (UUID, String, String, Date?, String, [UUID], Bool, String, String, String, Bool, [ContactCustomField]) -> Void,
        onDelete: ((ContactCard) -> Void)? = nil
    ) {
        self.existingContact = existingContact
        self.onSave = onSave
        self.onDelete = onDelete
        self.draftContactID = existingContact?.id ?? UUID()

        _displayName = State(initialValue: existingContact?.displayName ?? "")
        _relationshipLabel = State(initialValue: existingContact?.relationshipLabel ?? "")
        _notes = State(initialValue: existingContact?.notes ?? "")
        _email = State(initialValue: existingContact?.email ?? "")
        _phone = State(initialValue: existingContact?.phone ?? "")
        _address = State(initialValue: existingContact?.address ?? "")
        _selectedLabelIDs = State(initialValue: Set(existingContact?.labelIDs ?? []))
        _hasBirthday = State(initialValue: existingContact?.birthday != nil)
        _birthday = State(initialValue: existingContact?.birthday ?? Date())
        _addBirthdayDateCard = State(initialValue: existingContact?.birthday == nil)
        _hasAvatar = State(initialValue: existingContact?.hasAvatar ?? false)
        _avatarImage = State(initialValue: nil)
        _customFields = State(initialValue: existingContact?.customFields ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(existingContact == nil ? "New Contact Card" : "Edit Contact Card")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.primary)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Avatar picker row
                    HStack(spacing: Spacing.md) {
                        ZStack(alignment: .topTrailing) {
                            Button(action: pickAvatar) {
                                avatarEditorCircle(size: 60)
                            }
                            .buttonStyle(.plain)

                            if hasAvatar {
                                Button(action: removeAvatar) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(CiderFont.title)
                                        .foregroundColor(CiderColors.secondary)
                                        .background(
                                            Circle()
                                                .fill(CiderColors.surfaceSubtle)
                                                .padding(-1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Button(action: pickAvatar) {
                                Text(hasAvatar ? "Change Photo" : "Add Photo")
                                    .font(CiderFont.bodyMedium)
                                    .foregroundColor(CiderColors.controlAccent)
                            }
                            .buttonStyle(.plain)

                            Text("Tap to choose from your files")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TextField("Name", text: $displayName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Relationship", text: $relationshipLabel)
                            .textFieldStyle(.roundedBorder)

                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)

                        TextField("Phone", text: $phone)
                            .textFieldStyle(.roundedBorder)

                        TextField("Address", text: $address, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...3)

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

                        fieldsSection

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
                }
            }
            .frame(maxHeight: 500)

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
                        draftContactID,
                        displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        relationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        hasBirthday ? birthday : nil,
                        notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        Array(selectedLabelIDs),
                        hasBirthday && addBirthdayDateCard,
                        email.trimmingCharacters(in: .whitespacesAndNewlines),
                        phone.trimmingCharacters(in: .whitespacesAndNewlines),
                        address.trimmingCharacters(in: .whitespacesAndNewlines),
                        hasAvatar,
                        sanitizedCustomFields
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 440, maxWidth: 600)
        .task {
            guard let existingContact, existingContact.hasAvatar else { return }
            let url = ContactStorage.shared.avatarURL(for: existingContact.id)
            avatarImage = await loadAvatarFromDisk(url: url)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("Fields")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Button {
                    customFields.append(ContactCustomField(section: "Details", label: "", value: "", kind: .text))
                } label: {
                    Label("Add Field", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if customFields.isEmpty {
                Text("Add structured facts like favorite color, sizes, preferences, school info, phone, email, or links.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach($customFields) { $field in
                        customFieldRow(field: $field)
                    }
                }
            }
        }
        .padding(.top, Spacing.xs)
    }

    private func customFieldRow(field: Binding<ContactCustomField>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                TextField("Section", text: field.section)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 90)

                TextField("Label", text: field.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 110)

                Picker("Kind", selection: field.kind) {
                    ForEach(ContactCustomFieldKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 90)

                Button(role: .destructive) {
                    customFields.removeAll { $0.id == field.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: Spacing.xs) {
                TextField("Value", text: field.value, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                Toggle("Pinned", isOn: field.isPinned)
                    .toggleStyle(.checkbox)
                    .font(CiderFont.caption)
            }
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private var sanitizedCustomFields: [ContactCustomField] {
        customFields.compactMap { field in
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return ContactCustomField(
                id: field.id,
                section: field.section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Details" : field.section.trimmingCharacters(in: .whitespacesAndNewlines),
                label: field.label.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value,
                kind: field.kind,
                isPinned: field.isPinned
            )
        }
    }

    // MARK: - Avatar Circle

    @ViewBuilder
    private func avatarEditorCircle(size: CGFloat) -> some View {
        if let image = avatarImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(CiderColors.surfaceSubtle)
                .frame(width: size, height: size)
                .overlay(
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: "camera")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                        Text("Photo")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.quaternary)
                    }
                )
        }
    }

    // MARK: - Avatar Actions

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff]
        panel.title = "Choose Contact Photo"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        avatarImage = image
        hasAvatar = true
        _ = ContactStorage.shared.saveAvatar(image, for: draftContactID)
    }

    private func removeAvatar() {
        avatarImage = nil
        hasAvatar = false
        ContactStorage.shared.deleteAvatar(for: draftContactID)
    }

    private func loadAvatarFromDisk(url: URL) async -> NSImage? {
        let data: Data? = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        guard let data else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Label Chip

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
