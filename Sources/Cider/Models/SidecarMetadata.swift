import Foundation

/// Metadata for a single file, read from a `.cider-meta.json` sidecar file.
/// AI tools and Cider both read and write this format.
struct SidecarItemMetadata: Codable, Equatable {
    var tags: [String]?
    var summary: String?
    var date: String?
    var people: [String]?

    /// Stable item identity (Note UUID) persisted at the file level so
    /// identity can be recovered if the JSON/SQLite index is lost.
    /// Bookmarks use their own sidecar file; notes use this field inside
    /// the per-directory `.cider-meta.json`.
    var id: UUID?

    /// Any additional key-value pairs the AI tool wrote that Cider doesn't
    /// explicitly model. Preserved on round-trip so Cider doesn't destroy
    /// custom fields added by external tools.
    var extra: [String: AnyCodableValue]?

    var isEmpty: Bool {
        (tags ?? []).isEmpty &&
        summary == nil &&
        date == nil &&
        (people ?? []).isEmpty &&
        id == nil &&
        (extra ?? [:]).isEmpty
    }
}

/// The on-disk format: one `.cider-meta.json` per directory.
/// Maps filenames to their metadata.
struct SidecarFile: Codable, Equatable {
    var items: [String: SidecarItemMetadata]

    init(items: [String: SidecarItemMetadata] = [:]) {
        self.items = items
    }
}

// MARK: - AnyCodableValue

/// A type-erased Codable value for preserving unknown JSON fields.
/// Ensures Cider doesn't destroy metadata fields it doesn't know about.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
