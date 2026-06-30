import Foundation

enum SecondBrainActionReceiptLedgerError: Error, LocalizedError {
    case missingReceiptField(String)

    var errorDescription: String? {
        switch self {
        case .missingReceiptField(let field):
            return "Action receipt is missing required field '\(field)'"
        }
    }
}

struct SecondBrainActionReceiptRecord: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var command: String
    var action: String
    var actor: String
    var status: String
    var owner: SecondBrainOwnerRef?
    var sourceRefs: [String]
    var evidenceRefs: [String]
    var readOnly: Bool
    var changed: Bool
    var beforeJSON: String?
    var afterJSON: String?
    var errorCode: String?
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
    var correlationID: String?
    var receiptJSON: String?
    var createdAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        command: String,
        action: String,
        actor: String,
        status: String,
        owner: SecondBrainOwnerRef? = nil,
        sourceRefs: [String],
        evidenceRefs: [String],
        readOnly: Bool,
        changed: Bool,
        beforeJSON: String? = nil,
        afterJSON: String? = nil,
        errorCode: String? = nil,
        safeVerificationCommands: [String],
        safeNextCommands: [String],
        correlationID: String? = nil,
        receiptJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.action = action
        self.actor = actor
        self.status = status
        self.owner = owner
        self.sourceRefs = sourceRefs
        self.evidenceRefs = evidenceRefs
        self.readOnly = readOnly
        self.changed = changed
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.errorCode = errorCode
        self.safeVerificationCommands = safeVerificationCommands
        self.safeNextCommands = safeNextCommands
        self.correlationID = correlationID
        self.receiptJSON = receiptJSON
        self.createdAt = createdAt
    }

    init(receiptDictionary dict: [String: Any]) throws {
        guard let command = dict["command"] as? String else { throw SecondBrainActionReceiptLedgerError.missingReceiptField("command") }
        guard let action = dict["action"] as? String else { throw SecondBrainActionReceiptLedgerError.missingReceiptField("action") }
        let actor = dict["actor"] as? String ?? "cider-cli"
        let status = dict["status"] as? String ?? "succeeded"
        guard let readOnly = dict["readOnly"] as? Bool else { throw SecondBrainActionReceiptLedgerError.missingReceiptField("readOnly") }
        guard let changed = dict["changed"] as? Bool else { throw SecondBrainActionReceiptLedgerError.missingReceiptField("changed") }
        let owner: SecondBrainOwnerRef?
        if let ownerDict = dict["owner"] as? [String: Any],
           let ownerType = ownerDict["ownerType"] as? String,
           let ownerID = ownerDict["ownerID"] as? String {
            owner = SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID)
        } else {
            owner = nil
        }
        self.init(
            command: command,
            action: action,
            actor: actor,
            status: status,
            owner: owner,
            sourceRefs: dict["sourceRefs"] as? [String] ?? [],
            evidenceRefs: dict["evidenceRefs"] as? [String] ?? [],
            readOnly: readOnly,
            changed: changed,
            beforeJSON: Self.jsonString(from: dict["before"]),
            afterJSON: Self.jsonString(from: dict["after"]),
            errorCode: dict["errorCode"] as? String,
            safeVerificationCommands: dict["safeVerificationCommands"] as? [String] ?? [],
            safeNextCommands: dict["safeNextCommands"] as? [String] ?? [],
            correlationID: dict["correlationID"] as? String,
            receiptJSON: Self.jsonString(from: dict)
        )
    }

    private static func jsonString(from value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct SecondBrainActionReceiptFilter: Equatable {
    var owner: SecondBrainOwnerRef?
    var command: String?
    var commandPrefix: String?
    var family: String?
    var action: String?
    var actionPrefix: String?
    var actor: String?
    var status: String?
    var sourceRef: String?
    var evidenceRef: String?
    var since: Date?
    var before: Date?
    var limit: Int

    init(
        owner: SecondBrainOwnerRef? = nil,
        command: String? = nil,
        commandPrefix: String? = nil,
        family: String? = nil,
        action: String? = nil,
        actionPrefix: String? = nil,
        actor: String? = nil,
        status: String? = nil,
        sourceRef: String? = nil,
        evidenceRef: String? = nil,
        since: Date? = nil,
        before: Date? = nil,
        limit: Int = 20
    ) {
        self.owner = owner
        self.command = command
        self.commandPrefix = commandPrefix
        self.family = family
        self.action = action
        self.actionPrefix = actionPrefix
        self.actor = actor
        self.status = status
        self.sourceRef = sourceRef
        self.evidenceRef = evidenceRef
        self.since = since
        self.before = before
        self.limit = max(1, min(limit, 100))
    }
}

struct SecondBrainActionReceiptRecapEntry: Equatable {
    var id: String
    var command: String
    var action: String
    var status: String
    var readOnly: Bool
    var changed: Bool
    var createdAt: Date
    var sourceRefs: [String]
    var evidenceRefs: [String]
    var safeVerificationCommands: [String]
    var truthBoundary: String
    var outcomeBoundary: String
    var receiptTruthBoundary: String?
    var displaySummary: String
    var owner: SecondBrainOwnerRef?
}

struct SecondBrainActionReceiptRecapGroup: Equatable {
    var family: String
    var command: String
    var status: String
    var count: Int
    var latestAt: Date
    var changedCount: Int
    var readOnlyCount: Int
    var entries: [SecondBrainActionReceiptRecapEntry]
}

struct SecondBrainActionReceiptRecap: Equatable {
    var filter: SecondBrainActionReceiptFilter
    var totalCount: Int
    var groups: [SecondBrainActionReceiptRecapGroup]
    var safeVerificationCommands: [String]
    var truthBoundary: String = "action_receipt_not_fact_truth"
    var outcomeBoundary: String = "receipt_proves_command_outcome_only"
}

@MainActor
final class SecondBrainActionReceiptLedgerService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    @discardableResult
    func record(_ receipt: SecondBrainActionReceiptRecord) throws -> String {
        let stmt = try database.prepare("""
            INSERT INTO action_receipts (
                id, command, action, actor, status, owner_type, owner_id,
                source_refs_json, evidence_refs_json, read_only, changed,
                before_json, after_json, error_code, safe_verification_commands,
                safe_next_commands, correlation_id, receipt_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(receipt.id, at: 1)
            .bind(receipt.command, at: 2)
            .bind(receipt.action, at: 3)
            .bind(receipt.actor, at: 4)
            .bind(receipt.status, at: 5)
            .bind(receipt.owner?.ownerType, at: 6)
            .bind(receipt.owner?.ownerID, at: 7)
            .bind(DatabaseHelpers.encode(receipt.sourceRefs), at: 8)
            .bind(DatabaseHelpers.encode(receipt.evidenceRefs), at: 9)
            .bind(receipt.readOnly ? 1 : 0, at: 10)
            .bind(receipt.changed ? 1 : 0, at: 11)
            .bind(receipt.beforeJSON, at: 12)
            .bind(receipt.afterJSON, at: 13)
            .bind(receipt.errorCode, at: 14)
            .bind(DatabaseHelpers.encode(receipt.safeVerificationCommands), at: 15)
            .bind(DatabaseHelpers.encode(receipt.safeNextCommands), at: 16)
            .bind(receipt.correlationID, at: 17)
            .bind(receipt.receiptJSON ?? "{}", at: 18)
            .bind(DatabaseHelpers.encode(receipt.createdAt), at: 19)
        try stmt.step()
        return receipt.id
    }

    func inspect(id: String) throws -> SecondBrainActionReceiptRecord? {
        let stmt = try database.prepare(Self.selectSQL + " WHERE id = ? LIMIT 1;")
        stmt.bind(id, at: 1)
        guard try stmt.step() else { return nil }
        return Self.record(from: stmt)
    }

    func list(filter: SecondBrainActionReceiptFilter = .init()) throws -> [SecondBrainActionReceiptRecord] {
        var sql = Self.selectSQL
        var clauses: [String] = []
        var bindings: [String] = []
        if let owner = filter.owner {
            clauses.append("owner_type = ? AND owner_id = ?")
            bindings.append(owner.ownerType)
            bindings.append(owner.ownerID)
        }
        if let command = filter.command {
            clauses.append("command = ?")
            bindings.append(command)
        }
        if let commandPrefix = filter.commandPrefix {
            clauses.append("command LIKE ?")
            bindings.append(Self.sqlPrefixPattern(commandPrefix))
        }
        if let action = filter.action {
            clauses.append("action = ?")
            bindings.append(action)
        }
        if let actionPrefix = filter.actionPrefix {
            clauses.append("action LIKE ?")
            bindings.append(Self.sqlPrefixPattern(actionPrefix))
        }
        if let actor = filter.actor {
            clauses.append("actor = ?")
            bindings.append(actor)
        }
        if let status = filter.status {
            clauses.append("status = ?")
            bindings.append(status)
        }
        if let sourceRef = filter.sourceRef {
            clauses.append("source_refs_json LIKE ?")
            bindings.append(Self.jsonArrayContainsPattern(sourceRef))
        }
        if let evidenceRef = filter.evidenceRef {
            clauses.append("evidence_refs_json LIKE ?")
            bindings.append(Self.jsonArrayContainsPattern(evidenceRef))
        }
        if let since = filter.since {
            clauses.append("created_at >= ?")
            bindings.append(String(since.timeIntervalSince1970))
        }
        if let before = filter.before {
            clauses.append("created_at < ?")
            bindings.append(String(before.timeIntervalSince1970))
        }
        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }
        sql += " ORDER BY created_at DESC LIMIT ?;"
        let stmt = try database.prepare(sql)
        for (index, binding) in bindings.enumerated() {
            stmt.bind(binding, at: Int32(index + 1))
        }
        stmt.bind(filter.limit, at: Int32(bindings.count + 1))
        var records: [SecondBrainActionReceiptRecord] = []
        while try stmt.step() {
            records.append(Self.record(from: stmt))
        }
        if let family = filter.family {
            return records.filter { Self.commandFamily(for: $0) == family }
        }
        return records
    }

    func recap(filter: SecondBrainActionReceiptFilter = .init()) throws -> SecondBrainActionReceiptRecap {
        let records = try list(filter: filter)
        let entries = records.map(Self.recapEntry(from:))
        let grouped = Dictionary(grouping: entries) { entry in
            "\(Self.commandFamily(command: entry.command, receiptJSON: records.first { $0.id == entry.id }?.receiptJSON))\u{1F}\(entry.command)\u{1F}\(entry.status)"
        }
        let groups = grouped.values.map { groupEntries -> SecondBrainActionReceiptRecapGroup in
            let sortedEntries = groupEntries.sorted { $0.createdAt > $1.createdAt }
            let first = sortedEntries[0]
            let family = Self.commandFamily(command: first.command, receiptJSON: records.first { $0.id == first.id }?.receiptJSON)
            return SecondBrainActionReceiptRecapGroup(
                family: family,
                command: first.command,
                status: first.status,
                count: sortedEntries.count,
                latestAt: sortedEntries.map(\.createdAt).max() ?? first.createdAt,
                changedCount: sortedEntries.filter(\.changed).count,
                readOnlyCount: sortedEntries.filter(\.readOnly).count,
                entries: sortedEntries
            )
        }.sorted {
            if $0.latestAt != $1.latestAt { return $0.latestAt > $1.latestAt }
            if $0.family != $1.family { return $0.family < $1.family }
            if $0.command != $1.command { return $0.command < $1.command }
            return $0.status < $1.status
        }
        let safeCommands = Self.orderedUniqueStrings(
            groups.flatMap { group in
                group.entries.prefix(2).flatMap(\.safeVerificationCommands)
            }
        )
        return SecondBrainActionReceiptRecap(
            filter: filter,
            totalCount: entries.count,
            groups: groups,
            safeVerificationCommands: safeCommands
        )
    }

    private static let selectSQL = """
        SELECT id, command, action, actor, status, owner_type, owner_id,
               source_refs_json, evidence_refs_json, read_only, changed,
               before_json, after_json, error_code, safe_verification_commands,
               safe_next_commands, correlation_id, receipt_json, created_at
        FROM action_receipts
        """

    private static func jsonArrayContainsPattern(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "%\"\(escaped)\"%"
    }

    private static func sqlPrefixPattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    private static func recapEntry(from record: SecondBrainActionReceiptRecord) -> SecondBrainActionReceiptRecapEntry {
        var commands = [
            "cider-cli item action-ledger inspect \(record.id) --json",
        ] + record.safeVerificationCommands
        if let owner = record.owner {
            commands.append("cider-cli item context \(owner.ownerType) \(owner.ownerID) --max-history 10 --json")
        }
        let safeCommands = orderedUniqueStrings(commands)
        return SecondBrainActionReceiptRecapEntry(
            id: record.id,
            command: record.command,
            action: record.action,
            status: record.status,
            readOnly: record.readOnly,
            changed: record.changed,
            createdAt: record.createdAt,
            sourceRefs: record.sourceRefs,
            evidenceRefs: record.evidenceRefs,
            safeVerificationCommands: safeCommands,
            truthBoundary: "action_receipt_not_fact_truth",
            outcomeBoundary: "receipt_proves_command_outcome_only",
            receiptTruthBoundary: receiptMetadata(record.receiptJSON)["truthBoundary"] as? String,
            displaySummary: displaySummary(for: record),
            owner: record.owner
        )
    }

    private static func displaySummary(for record: SecondBrainActionReceiptRecord) -> String {
        let mode = record.readOnly ? "read-only" : "mutation"
        let change = record.changed ? "changed" : "unchanged"
        return "\(record.command) \(record.status) (\(mode), \(change))"
    }

    private static func commandFamily(for record: SecondBrainActionReceiptRecord) -> String {
        commandFamily(command: record.command, receiptJSON: record.receiptJSON)
    }

    private static func commandFamily(command: String, receiptJSON: String?) -> String {
        if let family = receiptMetadata(receiptJSON)["commandFamily"] as? String, !family.isEmpty {
            return family
        }
        return command.split(separator: ".", maxSplits: 1).first.map(String.init) ?? command
    }

    private static func receiptMetadata(_ json: String?) -> [String: Any] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func record(from stmt: SQLStatement) -> SecondBrainActionReceiptRecord {
        let ownerType = stmt.optionalString(at: 5)
        let ownerID = stmt.optionalString(at: 6)
        let owner = ownerType.flatMap { type in ownerID.map { SecondBrainOwnerRef(ownerType: type, ownerID: $0) } }
        return SecondBrainActionReceiptRecord(
            id: stmt.string(at: 0),
            command: stmt.string(at: 1),
            action: stmt.string(at: 2),
            actor: stmt.string(at: 3),
            status: stmt.string(at: 4),
            owner: owner,
            sourceRefs: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 7)),
            evidenceRefs: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 8)),
            readOnly: stmt.int(at: 9) != 0,
            changed: stmt.int(at: 10) != 0,
            beforeJSON: stmt.optionalString(at: 11),
            afterJSON: stmt.optionalString(at: 12),
            errorCode: stmt.optionalString(at: 13),
            safeVerificationCommands: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 14)),
            safeNextCommands: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 15)),
            correlationID: stmt.optionalString(at: 16),
            receiptJSON: stmt.optionalString(at: 17),
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 18))
        )
    }
}
