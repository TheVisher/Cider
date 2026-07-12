import Foundation

/// Read-only duplicate detector for vault entities. It reports candidate groups only;
/// cleanup/merge/trash decisions remain entity-specific and human-reviewed.
struct VaultDuplicateAuditor {
    enum EntityType: String, Codable, Hashable {
        case folder
        case note
        case bookmark
        case contact
    }

    enum DuplicateKind: String, Codable, Hashable {
        case exactContent
        case canonicalURL
        case email
        case phone
        case normalizedName
    }

    enum Confidence: String, Codable, Hashable {
        case exact
        case likely
        case possible
    }

    struct Item: Codable, Hashable {
        let id: String
        let title: String
        let path: String?
        let value: String?
    }

    struct Finding: Codable, Hashable {
        let id: String
        let entityType: EntityType
        let kind: DuplicateKind
        let confidence: Confidence
        let summary: String
        let detail: String
        let items: [Item]
    }

    @MainActor
    static func scan() -> [Finding] {
        scan(
            notes: NotesStorage.shared.notes,
            bookmarks: VaultBookmarkService.shared.bookmarks,
            contacts: ContactStorage.shared.contacts
        )
    }

    static func scan(
        notes: [Note],
        bookmarks: [Bookmark],
        contacts: [ContactCard]
    ) -> [Finding] {
        findDuplicateNotes(notes)
            + findDuplicateBookmarks(bookmarks)
            + findDuplicateContacts(contacts)
    }

    static func findDuplicateNotes(_ notes: [Note]) -> [Finding] {
        let candidates = notes.compactMap { note -> (key: String, item: Item)? in
            let content = note.resolvedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameKey = normalizedDuplicateName(note.title.isEmpty ? note.relativePath : note.title)
            guard !nameKey.isEmpty else { return nil }
            // Empty Markdown notes can still be active duplicate rows/files after
            // sync/adoption drift (for example `CodexNote.md`, `CodexNote 2.md`).
            // Keep them in the read-only duplicate audit so doctor/list/hash scans
            // reconcile; cleanup remains human/CLI-reviewed because findings are
            // not auto-fixable.
            return (
                key: "\(nameKey)|\(content)",
                item: Item(
                    id: note.id.uuidString,
                    title: note.title,
                    path: note.relativePath.isEmpty ? nil : note.relativePath,
                    value: nil
                )
            )
        }
        return groupedFindings(
            candidates,
            entityType: .note,
            kind: .exactContent,
            confidence: .exact,
            idPrefix: "duplicate-note-content",
            summaryPrefix: "Exact duplicate note content"
        )
    }

    static func findDuplicateBookmarks(_ bookmarks: [Bookmark]) -> [Finding] {
        let candidates = bookmarks.compactMap { bookmark -> (key: String, item: Item)? in
            guard let canonical = canonicalBookmarkURL(bookmark.urlString), !canonical.isEmpty else { return nil }
            return (
                key: canonical,
                item: Item(
                    id: bookmark.id.uuidString,
                    title: bookmark.title,
                    path: bookmark.relativePath,
                    value: canonical
                )
            )
        }
        return groupedFindings(
            candidates,
            entityType: .bookmark,
            kind: .canonicalURL,
            confidence: .exact,
            idPrefix: "duplicate-bookmark-url",
            summaryPrefix: "Duplicate bookmark URL"
        )
    }

    static func findDuplicateContacts(_ contacts: [ContactCard]) -> [Finding] {
        let emailCandidates = contacts.compactMap { contact -> (key: String, item: Item)? in
            let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty else { return nil }
            return (
                key: email,
                item: Item(id: contact.id.uuidString, title: contact.displayName, path: nil, value: email)
            )
        }
        let phoneCandidates = contacts.compactMap { contact -> (key: String, item: Item)? in
            let phone = normalizedPhone(contact.phone)
            guard !phone.isEmpty else { return nil }
            return (
                key: phone,
                item: Item(id: contact.id.uuidString, title: contact.displayName, path: nil, value: phone)
            )
        }
        return groupedFindings(
            emailCandidates,
            entityType: .contact,
            kind: .email,
            confidence: .exact,
            idPrefix: "duplicate-contact-email",
            summaryPrefix: "Duplicate contact email"
        ) + groupedFindings(
            phoneCandidates,
            entityType: .contact,
            kind: .phone,
            confidence: .exact,
            idPrefix: "duplicate-contact-phone",
            summaryPrefix: "Duplicate contact phone"
        )
    }

    static func normalizedDuplicateName(_ input: String) -> String {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") || name.lowercased().hasSuffix(".webloc") || name.lowercased().hasSuffix(".vcf") {
            name = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        }
        name = name.replacingOccurrences(
            of: #"(?:\s+\d+)+$"#,
            with: "",
            options: .regularExpression
        )
        name = name.replacingOccurrences(of: #"\s+\(\d+\)$"#, with: "", options: .regularExpression)
        return name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalBookmarkURL(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased()
        else { return nil }
        components.scheme = components.scheme?.lowercased() ?? "https"
        components.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        components.fragment = nil
        let trackingPrefixes = ["utm_"]
        let trackingNames: Set<String> = ["_kx", "fbclid", "gclid", "mc_cid", "mc_eid", "igshid", "ref", "ref_src"]
        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !trackingNames.contains(name) && !trackingPrefixes.contains(where: { name.hasPrefix($0) })
            }
            .sorted { $0.name < $1.name }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        if components.path != "/" {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + components.path
        }
        return components.string?.lowercased()
    }

    static func normalizedPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 11, digits.first == "1" {
            return String(digits.dropFirst())
        }
        return String(digits)
    }

    private static func groupedFindings(
        _ candidates: [(key: String, item: Item)],
        entityType: EntityType,
        kind: DuplicateKind,
        confidence: Confidence,
        idPrefix: String,
        summaryPrefix: String
    ) -> [Finding] {
        Dictionary(grouping: candidates, by: \.key)
            .filter { $0.value.count > 1 }
            .map { key, grouped in
                let items = grouped.map(\.item).sorted { $0.title < $1.title }
                let titles = items.map(\.title).joined(separator: ", ")
                let paths = items.compactMap(\.path).joined(separator: ", ")
                let detail = paths.isEmpty
                    ? "\(items.count) \(entityType.rawValue) records share \(kind.rawValue): \(key)."
                    : "\(items.count) \(entityType.rawValue) records share \(kind.rawValue): \(key). Paths: \(paths)."
                return Finding(
                    id: "\(idPrefix)-\(abs(key.hashValue))",
                    entityType: entityType,
                    kind: kind,
                    confidence: confidence,
                    summary: "\(summaryPrefix): \(titles)",
                    detail: detail,
                    items: items
                )
            }
            .sorted { $0.summary < $1.summary }
    }
}
