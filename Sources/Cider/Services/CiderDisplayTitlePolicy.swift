import Foundation

enum CiderDisplayTitlePolicy {
    static let maximumTitleLength = 160
    static let maximumTitleBaseLength = 120

    enum ValidationError: Error, Equatable, LocalizedError {
        case empty(String)
        case containsControlCharacters(String)
        case tooLong(String, maximum: Int)

        var errorDescription: String? {
            switch self {
            case .empty(let field):
                return "\(field) must not be blank."
            case .containsControlCharacters(let field):
                return "\(field) must not contain control characters."
            case .tooLong(let field, let maximum):
                return "\(field) must be at most \(maximum) characters."
            }
        }
    }

    static func normalizedTitle(_ raw: String, field: String = "Title") throws -> String {
        try normalized(raw, field: field, maximum: maximumTitleLength)
    }

    static func normalizedTitleBase(_ raw: String, field: String = "Media title base") throws -> String {
        try normalized(raw, field: field, maximum: maximumTitleBaseLength)
    }

    static func normalized(
        _ raw: String,
        field: String,
        maximum: Int
    ) throws -> String {
        guard raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ValidationError.containsControlCharacters(field)
        }
        let value = raw.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ValidationError.empty(field) }
        guard value.count <= maximum else { throw ValidationError.tooLong(field, maximum: maximum) }
        return value
    }
}
