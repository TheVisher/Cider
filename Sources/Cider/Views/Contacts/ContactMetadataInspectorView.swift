import SwiftUI

struct ContactMetadataDraft: Equatable {
    var displayName: String
    var relationshipLabel: String
    var birthday: Date?
    var notes: String
    var email: String
    var phone: String
    var address: String
    var labelIDs: [UUID]
    var customFields: [ContactCustomField]

    init(contact: ContactCard) {
        displayName = contact.displayName
        relationshipLabel = contact.relationshipLabel
        birthday = contact.birthday
        notes = contact.notes
        email = contact.email
        phone = contact.phone
        address = contact.address
        labelIDs = contact.labelIDs
        customFields = contact.customFields
    }

    mutating func addField(section: String, label: String, value: String, kind: ContactCustomFieldKind, isPinned: Bool) -> UUID {
        let field = ContactCustomField(section: section, label: label, value: value, kind: kind, isPinned: isPinned)
        customFields.append(field)
        return field.id
    }

    mutating func updateField(id: UUID, section: String, label: String, value: String, kind: ContactCustomFieldKind, isPinned: Bool) {
        guard let index = customFields.firstIndex(where: { $0.id == id }) else { return }
        customFields[index].section = section
        customFields[index].label = label
        customFields[index].value = value
        customFields[index].kind = kind
        customFields[index].isPinned = isPinned
    }

    mutating func deleteField(id: UUID) {
        customFields.removeAll { $0.id == id }
    }

    mutating func moveField(id: UUID, by offset: Int) {
        guard let index = customFields.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + offset
        guard customFields.indices.contains(targetIndex) else { return }

        let field = customFields.remove(at: index)
        customFields.insert(field, at: targetIndex)
    }

    func apply(to contact: ContactCard) -> ContactCard {
        var updated = contact
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.relationshipLabel = relationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.birthday = birthday
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.labelIDs = labelIDs
        updated.customFields = customFields.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return updated
    }
}

struct ContactMetadataInspectorView: View {
    let contact: ContactCard
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?
    var onSaveContact: ((ContactCard) -> Void)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var draft: ContactMetadataDraft
    @State private var isEditing = false
    @State private var isEssentialsExpanded = true
    @State private var isLinkedExpanded = true
    @State private var isNotesExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isInfoExpanded = true
    @State private var saveError: String?

    init(
        contact: ContactCard,
        onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil,
        canOpenLinkedRef: ((LibraryEntityRef) -> Bool)? = nil,
        onSaveContact: ((ContactCard) -> Void)? = nil
    ) {
        self.contact = contact
        self.onOpenLinkedRef = onOpenLinkedRef
        self.canOpenLinkedRef = canOpenLinkedRef
        self.onSaveContact = onSaveContact
        _draft = State(initialValue: ContactMetadataDraft(contact: contact))
    }

    var body: some View {
        ItemMetadataInspectorView {
            titleSection
            Divider().background(CiderColors.separator)
            essentialsSection
            Divider().background(CiderColors.separator)
            linkedSection
            Divider().background(CiderColors.separator)
            notesSection
            Divider().background(CiderColors.separator)
            labelsSection
            Divider().background(CiderColors.separator)
            infoSection
            editFooter
        }
        .onChange(of: contact.id) { _, _ in
            draft = ContactMetadataDraft(contact: contact)
            isEditing = false
            saveError = nil
        }
    }

    private var titleSection: some View {
        Group {
            if isEditing {
                TextField("Name", text: $draft.displayName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodySemibold)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceSubtle)
                    )
            } else {
                Text(contact.displayName)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(3)
            }
        }
        .padding(.bottom, Spacing.md)
    }

    private var essentialsSection: some View {
        ItemMetadataSectionView(title: "Essentials", isExpanded: $isEssentialsExpanded) {
            if isEditing {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField("Relationship", text: $draft.relationshipLabel)
                        TextField("Email", text: $draft.email)
                        TextField("Phone", text: $draft.phone)
                        TextField("Address", text: $draft.address, axis: .vertical)
                            .lineLimit(2...4)

                        Toggle("Has Birthday", isOn: hasBirthdayBinding)
                            .toggleStyle(.checkbox)
                            .font(CiderFont.caption)

                        if draft.birthday != nil {
                            DatePicker("Birthday", selection: birthdayBinding, displayedComponents: [.date])
                                .font(CiderFont.caption)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    customFieldsEditor
                }
            } else {
                let rows = ContactProfileEssentials.rows(for: contact, labels: labelStorage.labels).map {
                    ItemMetadataRow(id: $0.id, symbol: $0.symbol, title: $0.text)
                }
                if rows.isEmpty {
                    emptyText("No essentials saved.")
                } else {
                    ItemMetadataRowsView(rows: rows)
                }
            }
        }
    }

    private var linkedSection: some View {
        ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
            if relatedRows.isEmpty {
                emptyText("No linked items.")
            } else {
                ItemMetadataRowsView(
                    rows: relatedRows,
                    onOpenRef: onOpenLinkedRef,
                    canOpenRef: canOpenLinkedRef
                )
            }
        }
    }

    private var notesSection: some View {
        ItemMetadataSectionView(title: "Notes", isExpanded: $isNotesExpanded) {
            if isEditing {
                TextEditor(text: $draft.notes)
                    .font(CiderFont.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceSubtle)
                    )
            } else {
                if contact.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyText("No notes saved.")
                } else {
                    ContactMetadataMarkdownText(markdown: contact.notes, contact: contact)
                }
            }
        }
    }

    private var labelsSection: some View {
        ItemMetadataSectionView(title: "Labels", isExpanded: $isLabelsExpanded) {
            if isEditing {
                if labelStorage.labels.isEmpty {
                    emptyText("No labels available.")
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(labelStorage.labels) { label in
                            Toggle(label.name, isOn: labelBinding(for: label.id))
                                .toggleStyle(.checkbox)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.secondary)
                        }
                    }
                }
            } else {
                let labels = labelStorage.labels.filter { contact.labelIDs.contains($0.id) }
                if labels.isEmpty {
                    emptyText("No labels.")
                } else {
                    ItemMetadataRowsView(rows: labels.map {
                        ItemMetadataRow(id: "label-\($0.id.uuidString)", symbol: "tag", title: $0.name)
                    })
                }
            }
        }
    }

    private var infoSection: some View {
        ItemMetadataSectionView(title: "Info", isExpanded: $isInfoExpanded) {
            ItemMetadataRowsView(rows: ItemMetadataInfoRows.rows(
                createdAt: contact.createdAt,
                updatedAt: contact.updatedAt,
                typeLabel: "Contact"
            ))
        }
    }

    private var editFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let saveError {
                Text(saveError)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
            }

            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                if isEditing {
                    Button("Cancel") {
                        draft = ContactMetadataDraft(contact: contact)
                        isEditing = false
                        saveError = nil
                    }
                    .buttonStyle(.borderless)

                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Edit") {
                        draft = ContactMetadataDraft(contact: contact)
                        isEditing = true
                        saveError = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.top, Spacing.md)
    }

    private var customFieldsEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("Custom Fields")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Spacer(minLength: 0)
                Button {
                    _ = draft.addField(section: "Details", label: "", value: "", kind: .text, isPinned: false)
                } label: {
                    Label("Add Field", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if draft.customFields.isEmpty {
                emptyText("No custom fields.")
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(draft.customFields) { field in
                        if let index = draft.customFields.firstIndex(where: { $0.id == field.id }) {
                            customFieldEditor(field: $draft.customFields[index], position: index)
                        }
                    }
                }
            }
        }
    }

    private func customFieldEditor(field: Binding<ContactCustomField>, position: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                TextField("Section", text: field.section)
                    .textFieldStyle(.roundedBorder)

                TextField("Label", text: field.label)
                    .textFieldStyle(.roundedBorder)

                Button {
                    draft.moveField(id: field.wrappedValue.id, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(position == 0)
                .help("Move field up")

                Button {
                    draft.moveField(id: field.wrappedValue.id, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(position >= draft.customFields.count - 1)
                .help("Move field down")

                Button(role: .destructive) {
                    draft.deleteField(id: field.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete field")
            }

            TextField("Value", text: field.value, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            HStack(spacing: Spacing.xs) {
                Picker("Kind", selection: field.kind) {
                    ForEach(ContactCustomFieldKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)

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

    private var hasBirthdayBinding: Binding<Bool> {
        Binding(
            get: { draft.birthday != nil },
            set: { hasBirthday in
                draft.birthday = hasBirthday ? (draft.birthday ?? Date()) : nil
            }
        )
    }

    private var birthdayBinding: Binding<Date> {
        Binding(
            get: { draft.birthday ?? Date() },
            set: { draft.birthday = $0 }
        )
    }

    private func labelBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.labelIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    if !draft.labelIDs.contains(id) {
                        draft.labelIDs.append(id)
                    }
                } else {
                    draft.labelIDs.removeAll { $0 == id }
                }
            }
        )
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.quaternary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        let updated = draft.apply(to: contact)
        guard !updated.displayName.isEmpty else {
            saveError = "Name is required."
            return
        }
        guard ContactStorage.shared.updateContact(updated) else {
            saveError = "Could not save contact."
            return
        }
        onSaveContact?(ContactStorage.shared.contact(for: updated.id) ?? updated)
        isEditing = false
        saveError = nil
    }

    private var relatedRows: [ItemMetadataRow] {
        let contactRef = LibraryEntityRef(type: .contact, entityID: contact.id)
        let refs = (try? ItemLinkService.shared.relatedRefs(for: contactRef)) ?? []
        return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
    }
}

private struct ContactMetadataMarkdownText: View {
    let markdown: String
    let contact: ContactCard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let text):
                    Text(inlineMarkdown(text))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text("•")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.quaternary)
                        Text(inlineMarkdown(text))
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let text):
                    Text(inlineMarkdown(text))
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lines: [Line] {
        let title = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return markdown.components(separatedBy: .newlines).compactMap { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let heading = parseHeading(trimmed) {
                guard heading.lowercased() != title else { return nil }
                return .heading(heading)
            }

            if let bullet = parseBullet(trimmed) {
                return .bullet(bullet)
            }

            return .paragraph(trimmed)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    private func parseHeading(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("#") else { return nil }
        let text = trimmed.drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func parseBullet(_ trimmed: String) -> String? {
        guard let first = trimmed.first, first == "-" || first == "*" else { return nil }
        let text = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private enum Line {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }
}
