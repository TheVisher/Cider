import AppKit
import SwiftUI

struct ContactDetailView: View {
    let contact: ContactCard
    var onEdit: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var onOpenRelated: ((LibraryEntityRef) -> Void)? = nil

    @State private var selectedTab: ContactProfileTab = .overview
    @State private var isEssentialsExpanded = true
    @State private var avatarImage: NSImage?
    @State private var draftNotes = ""
    @State private var hasUnsavedNotes = false
    @State private var isEditingNotes = false

    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            profileHeader
            tabBar

            Divider()

            ViewThatFits(in: .horizontal) {
                if ContactProfileEssentials.shouldShowRail(for: selectedTab) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        tabContent
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        essentialsRail
                            .frame(width: 230)
                    }
                } else {
                    tabContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    if ContactProfileEssentials.shouldShowRail(for: selectedTab) {
                        collapsibleEssentials
                    }
                    tabContent
                }
            }

            Divider()

            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                if let onEdit {
                    Button("Edit") {
                        saveNotesIfNeeded()
                        onEdit()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(CiderColors.secondary)
                }

                if let onDismiss {
                    Button("Done") {
                        saveNotesIfNeeded()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task(id: contact.updatedAt) {
            await loadAvatar()
        }
        .onAppear {
            draftNotes = contact.notes
            hasUnsavedNotes = false
        }
        .onChange(of: contact.id) { _, _ in
            draftNotes = contact.notes
            hasUnsavedNotes = false
        }
        .onChange(of: contact.notes) { _, notes in
            guard !hasUnsavedNotes else { return }
            draftNotes = notes
        }
        .onDisappear {
            saveNotesIfNeeded()
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            avatarCircle(size: 84)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(contact.displayName)
                    .font(CiderFont.displaySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                if !contact.relationshipLabel.isEmpty {
                    Text(contact.relationshipLabel)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }

                if let birthday = contact.birthday {
                    let facts = ContactProfileBirthdayFacts(birthday: birthday)
                    Text("\(facts.age) years old · birthday \(birthday.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(ContactProfileTab.allCases) { tab in
                    Button {
                        withAnimation(reduceMotion ? .none : .snappy) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(selectedTab == tab ? CiderColors.primary : CiderColors.tertiary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(selectedTab == tab ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .overview:
                ContactProfileOverviewSection(contact: contact)
            case .birthday:
                ContactProfileBirthdaySection(contact: contact)
            case .favorites:
                ContactProfileFavoritesSection(contact: contact)
            case .notes:
                ContactProfileNotesSection(
                    contact: contact,
                    draftNotes: $draftNotes,
                    hasUnsavedChanges: $hasUnsavedNotes,
                    isEditing: $isEditingNotes,
                    onChange: { hasUnsavedNotes = true },
                    onSave: saveNotesIfNeeded
                )
            case .related:
                ContactProfileRelatedSection(contact: contact, onOpenRelated: onOpenRelated)
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
    }

    private var essentialsRows: [ContactProfileEssentialRow] {
        ContactProfileEssentials.rows(for: contact, labels: labelStorage.labels)
    }

    private var essentialsRail: some View {
        ContactProfileEssentialsPanel(rows: essentialsRows, isExpanded: .constant(true), canCollapse: false)
    }

    private var collapsibleEssentials: some View {
        ContactProfileEssentialsPanel(rows: essentialsRows, isExpanded: $isEssentialsExpanded, canCollapse: true)
    }

    @ViewBuilder
    private func avatarCircle(size: CGFloat) -> some View {
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
                    Text(ContactProfileAvatar.initials(for: contact))
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                )
        }
    }

    private func saveNotesIfNeeded() {
        guard hasUnsavedNotes else { return }
        var updated = contact
        updated.notes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if ContactStorage.shared.updateContact(updated) {
            hasUnsavedNotes = false
            isEditingNotes = false
        }
    }

    private func loadAvatar() async {
        guard contact.hasAvatar else {
            avatarImage = nil
            return
        }
        let url = ContactStorage.shared.avatarURL(for: contact.id)
        let data: Data? = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        if let data, let image = NSImage(data: data) {
            avatarImage = image
        } else {
            avatarImage = nil
        }
    }
}

private struct ContactProfileEssentialsPanel: View {
    let rows: [ContactProfileEssentialRow]
    @Binding var isExpanded: Bool
    let canCollapse: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                guard canCollapse else { return }
                withAnimation(reduceMotion ? .none : .snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("Essentials")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    if canCollapse {
                        Text(rows.isEmpty ? "Empty" : "\(rows.count) facts")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canCollapse)

            if isExpanded {
                if rows.isEmpty {
                    Text("Add phone, email, birthday, labels, or address from Edit.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(rows) { row in
                            ContactProfileDetailRow(icon: row.symbol, text: row.text)
                        }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }
}

private struct ContactProfileOverviewSection: View {
    let contact: ContactCard

    var body: some View {
        ContactProfileSection(title: "Overview", symbol: "person.text.rectangle") {
            let groups = ContactProfileCustomFields.groupedRows(for: contact)
            let noteLines = ContactProfileNotePreview.lines(from: contact.notes, contact: contact)

            if groups.isEmpty && noteLines.isEmpty {
                Text("Add notes, favorites, gift ideas, school details, preferences, or anything else worth remembering.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(group.section)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.quaternary)

                        ForEach(group.rows) { row in
                            ContactProfileDetailRow(icon: row.symbol, text: row.displayText)
                        }
                    }
                    .padding(.bottom, Spacing.xs)
                }

                if !noteLines.isEmpty {
                    ContactProfileTextPreview(lines: noteLines, lineLimit: 8)
                }
            }
        }
    }
}

private struct ContactProfileBirthdaySection: View {
    let contact: ContactCard
    @ObservedObject private var dateCards = DateCardStorage.shared

    var body: some View {
        ContactProfileSection(title: "Birthday", symbol: "gift") {
            if let birthday = contact.birthday {
                let facts = ContactProfileBirthdayFacts(birthday: birthday)
                ContactProfileDetailRow(
                    icon: "calendar",
                    text: birthday.formatted(.dateTime.month(.wide).day().year())
                )
                ContactProfileDetailRow(icon: "sparkles", text: "\(facts.age) years old")
                ContactProfileDetailRow(
                    icon: "arrow.clockwise",
                    text: "Next birthday: \(facts.nextBirthday.formatted(.dateTime.month(.wide).day().year()))"
                )

                ForEach(contact.linkedEntities.filter { $0.type == .dateCard }) { ref in
                    if let card = dateCards.dateCard(for: ref.entityID) {
                        ContactProfileDetailRow(
                            icon: "calendar.badge.clock",
                            text: "\(card.title) · \(card.startAt.formatted(.dateTime.month(.abbreviated).day()))"
                        )
                    }
                }
            } else {
                Text("No birthday saved yet.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
            }
        }
    }
}

private struct ContactProfileFavoritesSection: View {
    let contact: ContactCard

    var body: some View {
        ContactProfileSection(title: "Favorites", symbol: "star") {
            let favorites = favoriteLines
            if favorites.isEmpty {
                Text("Use Notes for favorite colors, foods, games, sizes, gift ideas, restaurants, and preferences. A dedicated favorites field can grow from real usage later.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(favorites, id: \.self) { line in
                    ContactProfileDetailRow(icon: "star", text: line)
                }
            }
        }
    }

    private var favoriteLines: [String] {
        ContactProfileFavorites.lines(for: contact)
    }
}

private struct ContactProfileNotesSection: View {
    let contact: ContactCard
    @Binding var draftNotes: String
    @Binding var hasUnsavedChanges: Bool
    @Binding var isEditing: Bool
    let onChange: () -> Void
    let onSave: () -> Void

    var body: some View {
        ContactProfileSection(title: "Notes", symbol: "note.text") {
            if isEditing {
                TextEditor(text: $draftNotes)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .onChange(of: draftNotes) { _, _ in onChange() }
            } else {
                let lines = ContactProfileNotePreview.lines(
                    from: draftNotes,
                    contact: contact,
                    includeRepresentedFacts: true
                )
                if lines.isEmpty {
                    Text("No notes saved yet.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ContactProfileTextPreview(lines: lines, lineLimit: nil)
                }
            }

            HStack(spacing: Spacing.sm) {
                Text(statusText)
                    .font(CiderFont.caption)
                    .foregroundColor(hasUnsavedChanges ? CiderColors.warning : CiderColors.quaternary)

                Spacer(minLength: 0)

                if isEditing {
                    Button("Cancel") {
                        draftNotes = contact.notes
                        hasUnsavedChanges = false
                        isEditing = false
                    }
                    .buttonStyle(.borderless)

                    Button("Save Notes") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)
                } else {
                    Button("Edit Notes") {
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var statusText: String {
        if isEditing {
            return hasUnsavedChanges ? "Unsaved changes" : "Editing Markdown"
        }
        return "Rendered preview"
    }
}

private struct ContactProfileRelatedSection: View {
    let contact: ContactCard
    var onOpenRelated: ((LibraryEntityRef) -> Void)? = nil

    var body: some View {
        ContactProfileSection(title: "Related", symbol: "link") {
            if relatedItems.isEmpty {
                Text("Linked bookmarks, notes, todos, dates, and files will appear here.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(relatedItems) { item in
                        if let onOpenRelated {
                            Button {
                                onOpenRelated(item.ref)
                            } label: {
                                relatedRow(item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            relatedRow(item)
                        }
                    }
                }
            }
        }
    }

    private var relatedItems: [ContactProfileRelatedItem] {
        let contactRef = LibraryEntityRef(type: .contact, entityID: contact.id)
        let refs: [LibraryEntityRef]
        if let serviceRefs = try? ItemLinkService.shared.relatedRefs(for: contactRef) {
            refs = serviceRefs
        } else {
            refs = ContactProfileRelatedRefs.merged(outgoing: contact.linkedEntities, backlinks: [], excluding: contactRef)
        }
        return ItemLinkService.shared.summaries(for: refs).map(ContactProfileRelatedItem.init(summary:))
    }

    private func relatedRow(_ item: ContactProfileRelatedItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: item.symbol)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(item.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

private struct ContactProfileSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                Text(title)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                content()
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct ContactProfileTextPreview: View {
    let lines: [String]
    let lineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(Array(lines.prefix(lineLimit ?? lines.count).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ContactProfileDetailRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
