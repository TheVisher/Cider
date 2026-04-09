import Foundation

/// Static helpers for encoding/decoding common Swift types to/from SQLite column values.
enum DatabaseHelpers {

    // MARK: - UUID ↔ TEXT

    /// Encode a UUID to its uppercased string representation for TEXT storage.
    static func encode(_ uuid: UUID) -> String {
        uuid.uuidString
    }

    /// Decode a TEXT column value to a UUID.
    static func decodeUUID(_ text: String) -> UUID? {
        UUID(uuidString: text)
    }

    // MARK: - Date ↔ REAL

    /// Encode a Date as a Double (timeIntervalSinceReferenceDate) for REAL storage.
    static func encode(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
    }

    /// Decode a REAL column value to a Date.
    static func decodeDate(_ real: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: real)
    }

    // MARK: - [String] ↔ JSON TEXT

    /// Encode a String array as a JSON TEXT value.
    static func encode(_ strings: [String]) -> String {
        (try? JSONEncoder().encode(strings)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Decode a JSON TEXT value to a String array.
    static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // MARK: - [UUID] ↔ JSON TEXT

    /// Encode a UUID array as a JSON TEXT value (array of UUID strings).
    static func encode(_ uuids: [UUID]) -> String {
        encode(uuids.map(\.uuidString))
    }

    /// Decode a JSON TEXT value to a UUID array.
    static func decodeUUIDArray(_ json: String?) -> [UUID] {
        decodeStringArray(json).compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Codable ↔ JSON TEXT

    /// Encode any Codable value to a JSON TEXT string.
    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a JSON TEXT string to any Decodable type.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
