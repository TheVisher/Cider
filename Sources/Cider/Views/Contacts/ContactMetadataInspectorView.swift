import SwiftUI

struct ContactMetadataInspectorView: View {
    let contact: ContactCard
    var onOpenRelated: ((LibraryEntityRef) -> Void)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @State private var isEssentialsExpanded = true
    @State private var isFolderExpanded = true
    @State private var isTagsExpanded = true
    @State private var isLinkedExpanded = true
    @State private var isNotesExpanded = true
    @State private var isFieldsExpanded = true
    @State private var isInfoExpanded = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleSection
                        .padding(.bottom, Spacing.md)

                    ForEach(visibleSections, id: \.self) { section in
                        metadataDivider
                        sectionView(section)
                            .padding(.vertical, Spacing.md)
                    }
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: BookmarksDesign.detailsSidebarFixedWidth)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(contact.displayName)
                .font(CiderFont.bodySemibold(scale: textScale))
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)

            if !contact.relationshipLabel.isEmpty {
                Text(contact.relationshipLabel)
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ContactMetadataInspectorSectionID) -> some View {
        switch section {
        case .essentials:
            metadataSection("Essentials", isExpanded: $isEssentialsExpanded) {
                if essentialsRows.isEmpty {
                    emptyText("No essentials saved.")
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(essentialsRows) { row in
                            metadataRow(symbol: row.symbol, title: row.text)
                        }
                    }
                }
            }
        case .folder:
            metadataSection("Folder", isExpanded: $isFolderExpanded) {
                folderMenu
            }
        case .tags:
            metadataSection("Tags", isExpanded: $isTagsExpanded) {
                tagsEditor
            }
        case .linked:
            metadataSection("Linked", isExpanded: $isLinkedExpanded) {
                ItemLinkMetadataEditor(
                    sourceRef: LibraryEntityRef(type: .contact, entityID: contact.id),
                    showsSectionHeader: false,
                    onOpenRef: onOpenRelated
                )
            }
        case .notes:
            metadataSection("Notes", isExpanded: $isNotesExpanded) {
                notesPreview
            }
        case .fields:
            metadataSection("Fields", isExpanded: $isFieldsExpanded) {
                fieldsPreview
            }
        case .info:
            metadataSection("Info", isExpanded: $isInfoExpanded) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    metadataRow(symbol: "calendar.badge.plus", title: "Created", value: contact.createdAt.formatted(date: .abbreviated, time: .shortened))
                    metadataRow(symbol: "clock", title: "Updated", value: contact.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    metadataRow(symbol: "person.crop.circle", title: "Type", value: "Contact")
                }
            }
        }
    }

    private func metadataSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(CiderFont.micro(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func metadataRow(symbol: String, title: String, value: String = "") -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(CiderFont.captionMedium(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.md, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                if !value.isEmpty {
                    Text(value)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var folderMenu: some View {
        Menu {
            Button("No Folder") {
                assignFolder(nil)
            }

            if !folders.isEmpty {
                Divider()
            }

            ForEach(folders) { folder in
                Button(folder.name) {
                    assignFolder(folder.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                Text(currentFolderName)
                    .font(CiderFont.body(scale: textScale))
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: BookmarksDesign.buttonTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var tagsEditor: some View {
        TagFlowLayout(spacing: Spacing.xs) {
            ForEach(assignedLabels) { label in
                TagPillView(
                    label: label,
                    onRemove: { toggleLabel(label.id) }
                )
            }

            Menu {
                if unassignedLabels.isEmpty && labelStorage.labels.isEmpty {
                    Button("New Tag...", action: createAndAssignLabel)
                } else {
                    ForEach(unassignedLabels) { label in
                        Button {
                            toggleLabel(label.id)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                                    .frame(width: BookmarksDesign.tagColorDotSize, height: BookmarksDesign.tagColorDotSize)
                                Text(label.name)
                            }
                        }
                    }

                    Divider()
                    Button("New Tag...", action: createAndAssignLabel)
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "plus")
                        .font(CiderFont.badgeSemibold)
                    Text("Add Tag")
                        .font(CiderFont.caption(scale: textScale))
                }
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.accentSubtle)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var notesPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            let lines = ContactProfileNotePreview.lines(
                from: contact.notes,
                contact: contact,
                includeRepresentedFacts: true
            )

            if lines.isEmpty {
                emptyText("No notes saved.")
            } else {
                ForEach(Array(lines.prefix(8).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(CiderFont.body(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var fieldsPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(fieldGroups) { group in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(group.section)
                        .font(CiderFont.captionSemibold(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(group.rows) { row in
                        metadataRow(symbol: row.symbol, title: row.displayText)
                    }
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.body(scale: textScale))
            .foregroundColor(CiderColors.quaternary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataDivider: some View {
        Divider()
            .background(CiderColors.separator)
    }

    private var visibleSections: [ContactMetadataInspectorSectionID] {
        ContactMetadataInspectorSections.visibleIDs(
            for: contact,
            labels: labelStorage.labels,
            relatedRefs: (try? ItemLinkService.shared.relatedRefs(for: LibraryEntityRef(type: .contact, entityID: contact.id))) ?? []
        )
    }

    private var essentialsRows: [ContactProfileEssentialRow] {
        ContactProfileEssentials.rows(for: contact, labels: labelStorage.labels)
    }

    private var fieldGroups: [ContactProfileFieldGroup] {
        ContactProfileCustomFields.groupedRows(for: contact)
    }

    private var folders: [Folder] {
        VaultFolderService.shared.legacyFolders
    }

    private var currentFolderName: String {
        guard let folderID = contact.folderID else { return "No Folder" }
        return folders.first(where: { $0.id == folderID })?.name ?? "No Folder"
    }

    private var assignedLabels: [CardLabel] {
        labelStorage.labels.filter { contact.labelIDs.contains($0.id) }
    }

    private var unassignedLabels: [CardLabel] {
        labelStorage.labels.filter { !contact.labelIDs.contains($0.id) }
    }

    private func assignFolder(_ folderID: UUID?) {
        var updated = contact
        updated.folderID = folderID
        _ = ContactStorage.shared.updateContact(updated)
    }

    private func toggleLabel(_ id: UUID) {
        var updated = contact
        if updated.labelIDs.contains(id) {
            updated.labelIDs.removeAll { $0 == id }
        } else {
            updated.labelIDs.append(id)
        }
        _ = ContactStorage.shared.updateContact(updated)
    }

    private func createAndAssignLabel() {
        let label = CardLabelStorage.shared.createLabel(
            name: "New Tag",
            colorHex: CardLabelStorage.randomPresetColor()
        )
        toggleLabel(label.id)
    }
}
