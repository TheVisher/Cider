import Foundation

enum ContactProfilePatchError: Error, Equatable, LocalizedError {
    case invalidBirthday(String)

    var errorDescription: String? {
        switch self {
        case .invalidBirthday(let value):
            return "Invalid birthday '\(value)'. Expected yyyy-MM-dd."
        }
    }
}

enum ContactProfilePatchField<Value> {
    case absent
    case null
    case value(Value)
}

struct ContactProfilePatch: Decodable {
    var displayName: ContactProfilePatchField<String> = .absent
    var relationship: ContactProfilePatchField<String> = .absent
    var birthday: ContactProfilePatchField<String> = .absent
    var notes: ContactProfilePatchField<String> = .absent
    var email: ContactProfilePatchField<String> = .absent
    var phone: ContactProfilePatchField<String> = .absent
    var address: ContactProfilePatchField<String> = .absent
    var linkedEntities: ContactProfilePatchField<[ContactProfileLinkedEntityPayload]> = .absent
    var fields: ContactProfilePatchField<[ContactProfileFieldPayload]> = .absent

    enum CodingKeys: String, CodingKey {
        case displayName
        case name
        case relationship
        case relationshipLabel
        case birthday
        case notes
        case email
        case phone
        case address
        case linkedEntities
        case fields
        case customFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodePatch(String.self, forKey: .displayName)
        if case .absent = displayName {
            displayName = try container.decodePatch(String.self, forKey: .name)
        }
        relationship = try container.decodePatch(String.self, forKey: .relationship)
        if case .absent = relationship {
            relationship = try container.decodePatch(String.self, forKey: .relationshipLabel)
        }
        birthday = try container.decodePatch(String.self, forKey: .birthday)
        notes = try container.decodePatch(String.self, forKey: .notes)
        email = try container.decodePatch(String.self, forKey: .email)
        phone = try container.decodePatch(String.self, forKey: .phone)
        address = try container.decodePatch(String.self, forKey: .address)
        linkedEntities = try container.decodePatch([ContactProfileLinkedEntityPayload].self, forKey: .linkedEntities)
        fields = try container.decodePatch([ContactProfileFieldPayload].self, forKey: .fields)
        if case .absent = fields {
            fields = try container.decodePatch([ContactProfileFieldPayload].self, forKey: .customFields)
        }
    }

    init() {}

    func apply(to contact: ContactCard) throws -> ContactCard {
        var updated = contact

        applyString(displayName, to: &updated.displayName)
        applyString(relationship, to: &updated.relationshipLabel)
        applyString(notes, to: &updated.notes)
        applyString(email, to: &updated.email)
        applyString(phone, to: &updated.phone)
        applyString(address, to: &updated.address)

        switch birthday {
        case .absent:
            break
        case .null:
            updated.birthday = nil
        case .value(let value):
            guard let parsed = ContactProfileJSON.parseBirthday(value) else {
                throw ContactProfilePatchError.invalidBirthday(value)
            }
            updated.birthday = parsed
        }

        switch linkedEntities {
        case .absent:
            break
        case .null:
            updated.linkedEntities = []
        case .value(let refs):
            updated.linkedEntities = refs.map(\.ref)
        }

        switch fields {
        case .absent:
            break
        case .null:
            updated.customFields = []
        case .value(let fields):
            updated.customFields = fields.map(\.field)
        }

        return updated
    }

    private func applyString(_ field: ContactProfilePatchField<String>, to value: inout String) {
        switch field {
        case .absent:
            break
        case .null:
            value = ""
        case .value(let newValue):
            value = newValue
        }
    }
}

struct ContactProfileLinkedEntityPayload: Decodable, Equatable {
    let ref: LibraryEntityRef

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case entityID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        let normalizedType = rawType == "event" ? "dateCard" : rawType
        let type = try LibraryEntityType(rawValue: normalizedType).unwrap(
            DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown linked entity type '\(rawType)'"
            )
        )
        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .entityID)
        let entityID = try UUID(uuidString: rawID).unwrap(
            DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Invalid linked entity id '\(rawID)'"
            )
        )
        ref = LibraryEntityRef(type: type, entityID: entityID)
    }
}

struct ContactProfileFieldPayload: Decodable, Equatable {
    let field: ContactCustomField

    enum CodingKeys: String, CodingKey {
        case id
        case section
        case label
        case value
        case kind
        case pinned
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
        let id = rawID.flatMap(UUID.init(uuidString:)) ?? UUID()
        let section = try container.decode(String.self, forKey: .section)
        let label = try container.decode(String.self, forKey: .label)
        let value = try container.decode(String.self, forKey: .value)
        let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind) ?? ContactCustomFieldKind.text.rawValue
        let kind = ContactCustomFieldKind(rawValue: kindRaw) ?? .text
        let pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
            ?? container.decodeIfPresent(Bool.self, forKey: .isPinned)
            ?? false
        field = ContactCustomField(id: id, section: section, label: label, value: value, kind: kind, isPinned: pinned)
    }
}

enum ContactProfileJSON {
    static func decodePatch(from json: String) throws -> ContactProfilePatch {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(ContactProfilePatch.self, from: data)
    }

    static func parseBirthday(_ value: String) -> Date? {
        CiderLocalDate.parseDashed(value)
    }

    static func formatBirthday(_ date: Date) -> String {
        CiderLocalDate.formatDashed(date)
    }

    static func profileDictionary(for contact: ContactCard) -> [String: Any] {
        var dict: [String: Any] = [
            "id": contact.id.uuidString,
            "displayName": contact.displayName,
            "relationship": contact.relationshipLabel,
            "birthday": contact.birthday.map(formatBirthday) as Any,
            "email": contact.email,
            "phone": contact.phone,
            "address": contact.address,
            "notes": contact.notes,
            "hasAvatar": contact.hasAvatar,
            "labelIDs": contact.labelIDs.map(\.uuidString),
            "linkedEntities": contact.linkedEntities.map { ref in
                [
                    "type": ref.type.rawValue,
                    "id": ref.entityID.uuidString
                ]
            },
            "fields": contact.customFields.map { field in
                [
                    "id": field.id.uuidString,
                    "section": field.section,
                    "label": field.label,
                    "value": field.value,
                    "kind": field.kind.rawValue,
                    "pinned": field.isPinned
                ] as [String: Any]
            },
            "created": ISO8601DateFormatter().string(from: contact.createdAt),
            "updated": ISO8601DateFormatter().string(from: contact.updatedAt)
        ]
        if contact.birthday == nil {
            dict["birthday"] = NSNull()
        }
        return dict
    }

}

private extension KeyedDecodingContainer {
    func decodePatch<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> ContactProfilePatchField<T> {
        guard contains(key) else { return .absent }
        if try decodeNil(forKey: key) {
            return .null
        }
        return .value(try decode(type, forKey: key))
    }
}

private extension Optional {
    func unwrap(_ error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}
