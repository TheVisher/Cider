import Foundation

enum ContactProfileTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case birthday = "Birthday"
    case favorites = "Favorites"
    case notes = "Notes"
    case related = "Related"

    var id: String { rawValue }
}

enum ContactProfileAvatar {
    static func initials(for contact: ContactCard) -> String {
        let parts = contact.displayName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }

        return String(contact.displayName.prefix(2)).uppercased()
    }
}

struct ContactProfileEssentialRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case relationship
        case birthday
        case phone
        case email
        case address
        case labels
        case customField
    }

    let id: String
    let kind: Kind
    let symbol: String
    let text: String
}

enum ContactProfileEssentials {
    static func shouldShowRail(for tab: ContactProfileTab) -> Bool {
        switch tab {
        case .birthday:
            false
        case .overview, .favorites, .notes, .related:
            true
        }
    }

    static func rows(
        for contact: ContactCard,
        labels: [CardLabel],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ContactProfileEssentialRow] {
        var rows: [ContactProfileEssentialRow] = []

        if !contact.relationshipLabel.isEmpty {
            rows.append(.init(
                id: "relationship",
                kind: .relationship,
                symbol: "heart",
                text: contact.relationshipLabel
            ))
        }

        if let birthday = contact.birthday {
            let facts = ContactProfileBirthdayFacts(birthday: birthday, now: now, calendar: calendar)
            rows.append(.init(
                id: "birthday",
                kind: .birthday,
                symbol: "gift",
                text: "\(birthday.formatted(.dateTime.month(.abbreviated).day().year())) · \(facts.age) years old"
            ))
        }

        if !contact.phone.isEmpty {
            rows.append(.init(id: "phone", kind: .phone, symbol: "phone", text: contact.phone))
        }

        if !contact.email.isEmpty {
            rows.append(.init(id: "email", kind: .email, symbol: "envelope", text: contact.email))
        }

        if !contact.address.isEmpty {
            rows.append(.init(id: "address", kind: .address, symbol: "mappin.and.ellipse", text: contact.address))
        }

        for field in contact.customFields where field.isPinned && !field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(.init(
                id: "field-\(field.id.uuidString)",
                kind: .customField,
                symbol: field.kind.contactProfileSymbol,
                text: ContactProfileCustomFields.displayText(for: field)
            ))
        }

        let matchingLabels = labels.filter { contact.labelIDs.contains($0.id) }
        if !matchingLabels.isEmpty {
            rows.append(.init(
                id: "labels",
                kind: .labels,
                symbol: "tag",
                text: matchingLabels.map(\.name).joined(separator: ", ")
            ))
        }

        return rows
    }
}

enum ContactMetadataInspectorSectionID: Hashable {
    case essentials
    case folder
    case tags
    case linked
    case notes
    case fields
    case info
}

enum ContactMetadataInspectorSections {
    static func visibleIDs(
        for contact: ContactCard,
        labels: [CardLabel],
        relatedRefs: [LibraryEntityRef]
    ) -> [ContactMetadataInspectorSectionID] {
        var sections: [ContactMetadataInspectorSectionID] = []

        if !ContactProfileEssentials.rows(for: contact, labels: labels).isEmpty {
            sections.append(.essentials)
        }

        sections.append(.folder)
        sections.append(.tags)
        sections.append(.linked)

        if !contact.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(.notes)
        }

        if !ContactProfileCustomFields.groupedRows(for: contact).isEmpty {
            sections.append(.fields)
        }

        sections.append(.info)
        _ = relatedRefs
        return sections
    }
}

enum ContactProfileNotePreview {
    static func lines(
        from markdown: String,
        contact: ContactCard,
        includeRepresentedFacts: Bool = false
    ) -> [String] {
        let representedFacts = representedFactKeys(for: contact)
        let title = contact.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var pendingHeading: String?
        var result: [String] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let isHeading = trimmed.hasPrefix("#")
            let line = readableLine(from: rawLine)
            guard !line.isEmpty else { continue }
            guard line.lowercased() != title else { continue }

            if isHeading {
                pendingHeading = line
                continue
            }

            if !includeRepresentedFacts,
               let factKey = factKey(from: line),
               representedFacts.contains(factKey) {
                continue
            }

            if let heading = pendingHeading {
                result.append(heading)
                pendingHeading = nil
            }

            result.append(line)
        }

        return result
    }

    static func readableLine(from rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        while line.hasPrefix("#") {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while line.hasPrefix("-") || line.hasPrefix("*") {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return line
    }

    private static func representedFactKeys(for contact: ContactCard) -> Set<String> {
        var keys = Set(contact.customFields.map { factKey(label: $0.label, value: $0.value) })
        if !contact.relationshipLabel.isEmpty {
            keys.insert(factKey(label: "Relationship", value: contact.relationshipLabel))
        }
        if let birthday = contact.birthday {
            keys.insert(factKey(label: "Birthday", value: birthday.formatted(.dateTime.month(.wide).day().year())))
            keys.insert(factKey(label: "Birthday", value: birthday.formatted(.dateTime.month(.abbreviated).day().year())))
        }
        if !contact.email.isEmpty {
            keys.insert(factKey(label: "Email", value: contact.email))
        }
        if !contact.phone.isEmpty {
            keys.insert(factKey(label: "Phone", value: contact.phone))
        }
        if !contact.address.isEmpty {
            keys.insert(factKey(label: "Address", value: contact.address))
        }
        return keys
    }

    private static func factKey(from line: String) -> String? {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return factKey(label: parts[0], value: parts[1])
    }

    private static func factKey(label: String, value: String) -> String {
        "\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

enum ContactProfileFavorites {
    static func lines(for contact: ContactCard) -> [String] {
        let fieldLines = ContactProfileCustomFields.rows(for: contact, section: "Favorites")
            .map(\.displayText)

        let noteLines = contact.notes
            .components(separatedBy: .newlines)
            .map(ContactProfileNotePreview.readableLine(from:))
            .filter { line in
                guard !line.isEmpty else { return false }
                guard !line.localizedCaseInsensitiveContains("favorites") else { return false }
                let lowercased = line.lowercased()
                return lowercased.contains("favourite")
                    || lowercased.contains("favorite")
                    || lowercased.contains("colour")
                    || lowercased.contains("color")
                    || lowercased.contains("likes")
                    || lowercased.contains("gift")
            }

        var seen = Set(fieldLines.map(normalizeLine))
        var lines = fieldLines
        for line in noteLines where !seen.contains(normalizeLine(line)) {
            seen.insert(normalizeLine(line))
            lines.append(line)
        }
        return lines
    }

    private static func normalizeLine(_ line: String) -> String {
        ContactProfileNotePreview.readableLine(from: line).lowercased()
    }
}

enum ContactProfileCardPreview {
    static func lines(for contact: ContactCard, limit: Int = 3) -> [String] {
        var lines: [String] = []

        lines.append(contentsOf: ContactProfileCustomFields.rows(for: contact).map(\.displayText))
        lines.append(contentsOf: ContactProfileNotePreview.lines(
            from: contact.notes,
            contact: contact,
            includeRepresentedFacts: true
        ))

        var seen: Set<String> = []
        let unique = lines.filter { line in
            let key = ContactProfileNotePreview.readableLine(from: line).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        return Array(unique.prefix(limit))
    }
}

struct ContactProfileFieldRow: Identifiable, Equatable {
    let id: UUID
    let section: String
    let label: String
    let value: String
    let kind: ContactCustomFieldKind
    let isPinned: Bool

    var symbol: String { kind.contactProfileSymbol }

    var displayText: String {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "\(label): \(value)"
    }
}

struct ContactProfileFieldGroup: Identifiable, Equatable {
    let section: String
    let rows: [ContactProfileFieldRow]

    var id: String { section }
}

enum ContactProfileCustomFields {
    static func rows(for contact: ContactCard, section: String? = nil) -> [ContactProfileFieldRow] {
        contact.customFields.compactMap { field in
            let trimmedValue = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { return nil }
            if let section, !field.section.caseInsensitiveEquals(section) {
                return nil
            }
            return ContactProfileFieldRow(
                id: field.id,
                section: normalizedSection(field.section),
                label: field.label,
                value: trimmedValue,
                kind: field.kind,
                isPinned: field.isPinned
            )
        }
    }

    static func groupedRows(for contact: ContactCard) -> [ContactProfileFieldGroup] {
        let rows = rows(for: contact)
        let orderedSections = rows.map(\.section).uniquedPreservingOrder()
        return orderedSections.map { section in
            ContactProfileFieldGroup(section: section, rows: rows.filter { $0.section == section })
        }
    }

    static func displayText(for field: ContactCustomField) -> String {
        let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return value
        }
        return "\(label): \(value)"
    }

    private static func normalizedSection(_ section: String) -> String {
        let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Details" : trimmed
    }
}

struct ContactProfileBirthdayFacts: Equatable {
    let age: Int
    let nextBirthday: Date
    let nextBirthdayComponents: DateComponents

    init(birthday: Date, now: Date = Date(), calendar: Calendar = .current) {
        let birthdayComponents = calendar.dateComponents([.month, .day], from: birthday)
        let currentYear = calendar.component(.year, from: now)
        let birthYear = calendar.component(.year, from: birthday)

        let birthdayThisYear = calendar.date(from: DateComponents(
            year: currentYear,
            month: birthdayComponents.month,
            day: birthdayComponents.day
        )) ?? birthday

        let nextYear = birthdayThisYear < calendar.startOfDay(for: now) ? currentYear + 1 : currentYear
        let next = calendar.date(from: DateComponents(
            year: nextYear,
            month: birthdayComponents.month,
            day: birthdayComponents.day
        )) ?? birthdayThisYear

        let hadBirthdayThisYear = birthdayThisYear <= now
        self.age = max(0, currentYear - birthYear - (hadBirthdayThisYear ? 0 : 1))
        self.nextBirthday = next
        self.nextBirthdayComponents = calendar.dateComponents([.month, .day], from: next)
    }
}

private extension ContactCustomFieldKind {
    var contactProfileSymbol: String {
        switch self {
        case .text:
            "text.alignleft"
        case .phone:
            "phone"
        case .email:
            "envelope"
        case .url:
            "link"
        case .date:
            "calendar"
        case .number:
            "number"
        }
    }
}

private extension String {
    func caseInsensitiveEquals(_ other: String) -> Bool {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in self where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct ContactProfileRelatedItem: Identifiable, Equatable {
    let ref: LibraryEntityRef
    let title: String
    let subtitle: String
    let symbol: String

    var id: String { ref.id }

    init(ref: LibraryEntityRef, title: String?, subtitle: String?, symbol: String? = nil) {
        self.ref = ref
        self.title = title?.isEmpty == false ? title! : "Missing \(ref.type.contactProfileDisplayName)"
        self.subtitle = subtitle?.isEmpty == false ? subtitle! : ref.entityID.uuidString
        self.symbol = symbol ?? ref.type.contactProfileSymbol
    }

    init(summary: ItemLinkSummary) {
        self.ref = summary.ref
        self.title = summary.title
        self.subtitle = summary.subtitle
        self.symbol = summary.symbol
    }
}

enum ContactProfileRelatedRefs {
    static func merged(outgoing: [LibraryEntityRef], backlinks: [LibraryEntityRef], excluding excluded: LibraryEntityRef? = nil) -> [LibraryEntityRef] {
        var seen: Set<String> = []
        var result: [LibraryEntityRef] = []
        for ref in outgoing + backlinks {
            if ref == excluded { continue }
            guard !seen.contains(ref.id) else { continue }
            seen.insert(ref.id)
            result.append(ref)
        }
        return result
    }
}

extension LibraryEntityType {
    var contactProfileDisplayName: String {
        switch self {
        case .bookmark:
            "bookmark"
        case .note:
            "note"
        case .dateCard:
            "date card"
        case .contact:
            "contact"
        case .todo:
            "todo"
        case .vaultFile:
            "file"
        case .externalFile:
            "file"
        case .session:
            "session"
        }
    }

    var contactProfileSymbol: String {
        switch self {
        case .bookmark:
            "bookmark"
        case .note:
            "note.text"
        case .dateCard:
            "calendar"
        case .contact:
            "person.crop.circle"
        case .todo:
            "checklist"
        case .vaultFile, .externalFile:
            "doc"
        case .session:
            "rectangle.stack"
        }
    }
}
