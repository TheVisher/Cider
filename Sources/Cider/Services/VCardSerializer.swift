import Foundation

/// Reads and writes ContactCard models as vCard 3.0 (.vcf) files.
/// Standard fields (FN, EMAIL, TEL, ADR, BDAY, NOTE) are interoperable with
/// Apple Contacts, Google, Outlook, etc. Cider-specific fields use X-CIDER-* properties.
enum VCardSerializer {

    // MARK: - Write

    /// Serializes a ContactCard to vCard 3.0 format.
    static func serialize(_ contact: ContactCard) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCARD")
        lines.append("VERSION:3.0")
        lines.append("UID:\(contact.id.uuidString)")
        lines.append("FN:\(escapeVCard(contact.displayName))")

        // Standard fields
        if !contact.email.isEmpty {
            lines.append("EMAIL;TYPE=INTERNET:\(escapeVCard(contact.email))")
        }
        if !contact.phone.isEmpty {
            lines.append("TEL:\(escapeVCard(contact.phone))")
        }
        if !contact.address.isEmpty {
            // ADR has structured components separated by semicolons.
            // We store a free-form string, so put it in the street field.
            lines.append("ADR:;;\(escapeVCard(contact.address));;;;")
        }
        if let birthday = contact.birthday {
            lines.append("BDAY:\(birthdayFormatter.string(from: birthday))")
        }
        if !contact.notes.isEmpty {
            lines.append("NOTE:\(escapeVCard(contact.notes))")
        }

        // Cider-specific extensions
        if !contact.relationshipLabel.isEmpty {
            lines.append("X-CIDER-RELATIONSHIP:\(escapeVCard(contact.relationshipLabel))")
        }
        if !contact.labelIDs.isEmpty {
            lines.append("X-CIDER-LABEL:\(contact.labelIDs.map(\.uuidString).joined(separator: ","))")
        }
        if !contact.linkedEntities.isEmpty {
            let refs = contact.linkedEntities.map { "\($0.type.rawValue):\($0.entityID.uuidString)" }
            lines.append("X-CIDER-LINKED:\(refs.joined(separator: ","))")
        }
        if !contact.customFields.isEmpty {
            lines.append("X-CIDER-FIELDS:\(escapeVCard(ContactCustomFieldCodec.encode(contact.customFields)))")
        }
        if contact.hasAvatar {
            lines.append("X-CIDER-HAS-AVATAR:TRUE")
        }
        lines.append("X-CIDER-CREATED:\(iso8601Formatter.string(from: contact.createdAt))")
        lines.append("X-CIDER-UPDATED:\(iso8601Formatter.string(from: contact.updatedAt))")

        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Parse

    /// Parses a vCard string into a ContactCard. Returns nil if the data is invalid.
    static func parse(_ string: String) -> ContactCard? {
        let lines = unfoldLines(string)

        guard lines.contains(where: { $0.hasPrefix("BEGIN:VCARD") }),
              lines.contains(where: { $0.hasPrefix("END:VCARD") }) else {
            return nil
        }

        var id: UUID?
        var displayName = ""
        var email = ""
        var phone = ""
        var address = ""
        var birthday: Date?
        var notes = ""
        var relationshipLabel = ""
        var labelIDs: [UUID] = []
        var linkedEntities: [LibraryEntityRef] = []
        var customFields: [ContactCustomField] = []
        var hasAvatar = false
        var createdAt: Date?
        var updatedAt: Date?

        for line in lines {
            let (key, value) = splitProperty(line)
            let baseKey = key.components(separatedBy: ";").first ?? key

            switch baseKey.uppercased() {
            case "UID":
                id = UUID(uuidString: value)
            case "FN":
                displayName = unescapeVCard(value)
            case "EMAIL":
                email = unescapeVCard(value)
            case "TEL":
                phone = unescapeVCard(value)
            case "ADR":
                // ADR is ;-separated: PO;Extended;Street;City;Region;Postal;Country
                // We stored free-form text in the street component
                let parts = value.components(separatedBy: ";")
                if parts.count >= 3 {
                    address = unescapeVCard(parts[2])
                } else {
                    address = unescapeVCard(value)
                }
            case "BDAY":
                birthday = birthdayFormatter.date(from: value)
            case "NOTE":
                notes = unescapeVCard(value)
            case "X-CIDER-RELATIONSHIP":
                relationshipLabel = unescapeVCard(value)
            case "X-CIDER-LABEL":
                labelIDs = value.components(separatedBy: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
            case "X-CIDER-LINKED":
                linkedEntities = parseLinkedEntities(value)
            case "X-CIDER-FIELDS":
                customFields = ContactCustomFieldCodec.decode(unescapeVCard(value))
            case "X-CIDER-HAS-AVATAR":
                hasAvatar = value.uppercased() == "TRUE"
            case "X-CIDER-CREATED":
                createdAt = iso8601Formatter.date(from: value)
            case "X-CIDER-UPDATED":
                updatedAt = iso8601Formatter.date(from: value)
            default:
                break
            }
        }

        guard let contactID = id, !displayName.isEmpty else { return nil }

        return ContactCard(
            id: contactID,
            displayName: displayName,
            relationshipLabel: relationshipLabel,
            birthday: birthday,
            notes: notes,
            email: email,
            phone: phone,
            address: address,
            hasAvatar: hasAvatar,
            labelIDs: labelIDs,
            linkedEntities: linkedEntities,
            customFields: customFields,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    // MARK: - Helpers

    /// vCard line folding: lines starting with a space or tab are continuations.
    private static func unfoldLines(_ string: String) -> [String] {
        var result: [String] = []
        for rawLine in string.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty { continue }
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Splits "KEY:value" or "KEY;param:value" into (key, value).
    private static func splitProperty(_ line: String) -> (String, String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let key = String(line[line.startIndex..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])
        return (key, value)
    }

    /// Escapes special characters for vCard text values.
    private static func escapeVCard(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Unescapes vCard text values.
    private static func unescapeVCard(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Parses "type:uuid,type:uuid" into LibraryEntityRef array.
    private static func parseLinkedEntities(_ value: String) -> [LibraryEntityRef] {
        value.components(separatedBy: ",").compactMap { pair in
            let parts = pair.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
            guard parts.count == 2,
                  let type = LibraryEntityType(rawValue: parts[0]),
                  let uuid = UUID(uuidString: parts[1]) else { return nil }
            return LibraryEntityRef(type: type, entityID: uuid)
        }
    }

    /// Birthday formatter uses the current timezone because BDAY is a calendar date,
    /// not a point in time. Using UTC would shift the date by -1 day in western timezones.
    private static let birthdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
