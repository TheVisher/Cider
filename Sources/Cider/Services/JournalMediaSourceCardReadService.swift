import Foundation

/// Projects durable Journal capture attachments into the existing Journal read
/// model. Capture attachments remain immutable provenance/source identity;
/// the linked VaultFile supplies the current canonical display title and the
/// immutable original/native preview target.
@MainActor
final class JournalMediaSourceCardReadService {
    private let database: CiderDatabase
    private let vaultRoot: URL
    private let fileManager: FileManager

    init(
        database: CiderDatabase = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.database = database
        self.vaultRoot = vaultRoot.standardizedFileURL
        self.fileManager = fileManager
    }

    func sourceCards(noteIDs: Set<UUID>) throws -> [JournalMediaSourceCard] {
        guard database.isOpen, !noteIDs.isEmpty else { return [] }
        let statement = try database.prepare("""
            SELECT a.id, a.source_attachment_id, a.filename, a.metadata, a.created_at,
                   i.id, i.relative_path, i.title
            FROM capture_attachments a
            JOIN items i ON i.id = json_extract(a.metadata, '$.vault_file_id')
                        AND i.type = 'vaultFile'
            WHERE json_extract(a.metadata, '$.journal_note_id') IS NOT NULL
            ORDER BY a.created_at ASC, a.attachment_index ASC, a.id ASC;
            """)
        var cards: [JournalMediaSourceCard] = []
        while try statement.step() {
            let metadata = DatabaseHelpers.decodeJSON(
                [String: String].self,
                from: statement.optionalString(at: 3)
            ) ?? [:]
            guard let rawNoteID = metadata["journal_note_id"],
                  let noteID = UUID(uuidString: rawNoteID),
                  noteIDs.contains(noteID),
                  let mediaItemID = UUID(uuidString: statement.string(at: 5)),
                  let kind = JournalMediaKind(rawValue: metadata["media_kind"] ?? ""),
                  let relativePath = statement.optionalString(at: 6),
                  Self.isSafeRelativePath(relativePath) else {
                continue
            }
            let url = vaultRoot.appendingPathComponent(relativePath).standardizedFileURL
            cards.append(.init(
                id: statement.string(at: 0),
                noteID: noteID,
                timestamp24Hour: metadata["journal_time"] ?? "",
                capturedAt: DatabaseHelpers.decodeDate(statement.double(at: 4)),
                kind: kind,
                displayTitle: statement.optionalString(at: 7)
                    ?? metadata["display_title"]
                    ?? statement.optionalString(at: 2).map { ($0 as NSString).deletingPathExtension }
                    ?? "Journal media",
                rawFilename: metadata["raw_filename"] ?? statement.optionalString(at: 2) ?? "",
                sourceID: metadata["source_id"] ?? statement.optionalString(at: 1) ?? "",
                mediaItemID: mediaItemID,
                relativePath: relativePath,
                isOriginalAvailable: Self.isContained(url, in: vaultRoot)
                    && fileManager.fileExists(atPath: url.path),
                transcription: JournalVoiceTranscription.read(from: metadata)
            ))
        }
        return cards
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }
}
