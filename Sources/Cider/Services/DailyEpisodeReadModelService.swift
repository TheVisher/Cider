import Foundation

struct DailyEpisodePreview {
    var date: String
    var title: String
    var exists: Bool
    var dailyJournal: DailyEpisodeSourceItem?
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var entries: [DailyEpisodeEntry]
    var explanation: String?
    var safeNextCommands: [String]
}

struct DailyEpisodeSourceItem: Equatable {
    var id: String
    var type: String
    var title: String
    var relativePath: String?

    var ref: String { "\(type):\(id)" }
}

struct DailyEpisodeEntry: Identifiable, Equatable {
    var id: String
    var date: String
    var time: String?
    var heading: String?
    var snippet: String
    var sourceItemRef: String
    var sourceLine: Int
    var provenanceRefs: [DailyEpisodeProvenanceRef]
}

struct DailyEpisodeProvenanceRef: Equatable {
    var ref: String
    var ownerType: String
    var ownerID: String
    var sourceKind: String
    var surface: String?
    var channel: String?
    var channelID: String?
    var threadID: String?
    var messageID: String?
    var senderID: String?
    var senderName: String?
    var sourceText: String?
    var metadata: [String: String]
    var createdAt: Date
}

@MainActor
final class DailyEpisodeReadModelService {
    private let database: CiderDatabase
    private let notesStorage: NotesStorage

    init(database: CiderDatabase = .shared, notesStorage: NotesStorage = .shared) {
        self.database = database
        self.notesStorage = notesStorage
    }

    func preview(date: String) throws -> DailyEpisodePreview {
        let title = "Daily Episode \(date)"
        let safeSearchCommand = "cider-cli item search \"\(date)\" --scope personalMemory --json"
        guard let journal = dailyJournalSourceItem(for: date) else {
            return DailyEpisodePreview(
                date: date,
                title: title,
                exists: false,
                dailyJournal: nil,
                sourceItemRefs: [],
                entries: [],
                explanation: "No daily journal note was found for \(date).",
                safeNextCommands: [
                    safeSearchCommand,
                    "cider-cli capture add --kind journal --date \(date) --stdin --json",
                ]
            )
        }

        let content = contentForNote(id: journal.id)
        let provenance = try captureProvenance(forNoteID: journal.id)
        let entries = parseEntries(
            content: content,
            date: date,
            sourceItemRef: journal.ref,
            provenance: provenance
        )

        return DailyEpisodePreview(
            date: date,
            title: title,
            exists: true,
            dailyJournal: journal,
            sourceItemRefs: [journal],
            entries: entries,
            explanation: entries.isEmpty
                ? "Daily journal note exists for \(date), but no timestamped entry slices were found."
                : nil,
            safeNextCommands: [
                "cider-cli item get note \(journal.id) --json",
                "cider-cli item context note \(journal.id) --json",
                safeSearchCommand,
            ]
        )
    }

    private func dailyJournalSourceItem(for date: String) -> DailyEpisodeSourceItem? {
        guard let note = notesStorage.notes.first(where: {
            $0.dailyJournalDateLabel == date
        }) else {
            return nil
        }
        return DailyEpisodeSourceItem(
            id: note.id.uuidString,
            type: "note",
            title: note.title,
            relativePath: note.relativePath.isEmpty ? nil : note.relativePath
        )
    }

    private func contentForNote(id: String) -> String {
        guard let uuid = UUID(uuidString: id),
              let note = notesStorage.notes.first(where: { $0.id == uuid }) else {
            return ""
        }
        return notesStorage.loadContent(for: note)
    }

    private func parseEntries(
        content: String,
        date: String,
        sourceItemRef: String,
        provenance: [DailyEpisodeProvenanceRef]
    ) -> [DailyEpisodeEntry] {
        let lines = content.components(separatedBy: .newlines)
        var parsed: [DailyEpisodeEntry] = []
        for slice in Self.parseJournalEntrySlices(lines: lines) {
            let matchingProvenance = provenance.filter { ref in
                ref.metadata["date"] == date
                    && ref.metadata["time"] == slice.time
                    && (ref.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) == slice.body
                        || ref.sourceText == nil)
            }
            parsed.append(DailyEpisodeEntry(
                id: "\(date)-\(slice.time)-line-\(slice.line)",
                date: date,
                time: slice.time,
                heading: slice.heading,
                snippet: Self.snippet(from: slice.body),
                sourceItemRef: sourceItemRef,
                sourceLine: slice.line,
                provenanceRefs: matchingProvenance
            ))
        }
        return parsed.sorted { lhs, rhs in
            switch (lhs.time, rhs.time) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.sourceLine < rhs.sourceLine
            }
        }
    }

    private static func parseJournalEntrySlices(lines: [String]) -> [(time: String, heading: String?, body: String, line: Int)] {
        var slices: [(time: String, heading: String?, body: String, line: Int)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let legacy = parseJournalEntryLine(line) {
                slices.append((time: legacy.time, heading: nil, body: legacy.body, line: index + 1))
                index += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("## ") else {
                index += 1
                continue
            }
            let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let time = String(heading.prefix(5))
            guard time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
                index += 1
                continue
            }

            let sourceLine = index + 1
            index += 1
            var bodyLines: [String] = []
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.hasPrefix("## ") { break }
                if !next.isEmpty && !next.localizedCaseInsensitiveContains("source:") {
                    bodyLines.append(lines[index])
                }
                index += 1
            }
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                slices.append((time: time, heading: heading, body: body, line: sourceLine))
            }
        }
        return slices
    }

    private static func parseJournalEntryLine(_ line: String) -> (time: String, body: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("- "), trimmed.count > 10 else { return nil }
        let afterBullet = String(trimmed.dropFirst(2))
        let time = String(afterBullet.prefix(5))
        guard time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let separator = " - "
        guard afterBullet.dropFirst(5).hasPrefix(separator) else { return nil }
        let body = String(afterBullet.dropFirst(5 + separator.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return (time, body)
    }

    private static func snippet(from body: String, limit: Int = 240) -> String {
        let normalized = body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<end])
    }

    private func captureProvenance(forNoteID noteID: String) throws -> [DailyEpisodeProvenanceRef] {
        guard database.isOpen else { return [] }
        let stmt = try database.prepare("""
            SELECT e.id, e.source_kind, e.surface, e.channel, e.channel_id, e.thread_id,
                   e.message_id, e.sender_id, e.sender_name, e.source_text,
                   e.metadata, e.created_at
            FROM owner_relations r
            JOIN capture_events e ON e.id = r.source_owner_id
            WHERE r.source_owner_type = 'capture_event'
              AND r.target_owner_type = 'note'
              AND r.target_owner_id = ?
              AND r.relation_type = 'produced_item'
            ORDER BY e.created_at ASC, e.id ASC;
            """)
        stmt.bind(noteID, at: 1)

        var refs: [DailyEpisodeProvenanceRef] = []
        while try stmt.step() {
            let id = stmt.string(at: 0)
            refs.append(DailyEpisodeProvenanceRef(
                ref: "capture_event:\(id)",
                ownerType: "capture_event",
                ownerID: id,
                sourceKind: stmt.string(at: 1),
                surface: stmt.optionalString(at: 2),
                channel: stmt.optionalString(at: 3),
                channelID: stmt.optionalString(at: 4),
                threadID: stmt.optionalString(at: 5),
                messageID: stmt.optionalString(at: 6),
                senderID: stmt.optionalString(at: 7),
                senderName: stmt.optionalString(at: 8),
                sourceText: stmt.optionalString(at: 9),
                metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 10)) ?? [:],
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11))
            ))
        }
        return refs
    }
}
