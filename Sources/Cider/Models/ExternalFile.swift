import Foundation
import CommonCrypto

/// A single `.md` file discovered inside a Linked Source directory.
/// Not persisted — rebuilt from the filesystem on every scan.
/// Identity is derived deterministically from the file path so it is
/// stable across app launches without storing anything to disk.
struct ExternalFile: Identifiable {
    var id: UUID          // deterministic UUID derived from absolute path
    var title: String     // filename without .md extension
    var path: URL         // absolute path to the .md file
    var sourceID: UUID    // which ExternalSource contains this file
    var sourceName: String // display name of the source (for card footer)
    var createdAt: Date   // from filesystem creation date attribute
    var modifiedAt: Date  // from filesystem modification date attribute

    /// Derives a stable UUID from the file's absolute path using SHA-256.
    /// The same path always produces the same UUID. If the file moves,
    /// it gets a new UUID — treated as a new item, same as any file editor.
    static func stableID(for path: String) -> UUID {
        guard let data = path.data(using: .utf8) else { return UUID() }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        // Take first 16 bytes and set RFC 4122 version 4 + variant bits
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variant
        return NSUUID(uuidBytes: &bytes) as UUID
    }
}

extension ExternalFile: Hashable {
    static func == (lhs: ExternalFile, rhs: ExternalFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
