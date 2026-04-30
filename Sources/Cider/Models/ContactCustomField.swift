import Foundation

enum ContactCustomFieldKind: String, Codable, CaseIterable, Hashable {
    case text
    case phone
    case email
    case url
    case date
    case number
}

struct ContactCustomField: Identifiable, Codable, Hashable {
    let id: UUID
    var section: String
    var label: String
    var value: String
    var kind: ContactCustomFieldKind
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        section: String,
        label: String,
        value: String,
        kind: ContactCustomFieldKind = .text,
        isPinned: Bool = false
    ) {
        self.id = id
        self.section = section
        self.label = label
        self.value = value
        self.kind = kind
        self.isPinned = isPinned
    }
}

enum ContactCustomFieldCodec {
    static func encode(_ fields: [ContactCustomField]) -> String {
        guard let data = try? JSONEncoder().encode(fields),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func decode(_ string: String?) -> [ContactCustomField] {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = string.data(using: .utf8),
              let fields = try? JSONDecoder().decode([ContactCustomField].self, from: data) else {
            return []
        }
        return fields
    }
}
