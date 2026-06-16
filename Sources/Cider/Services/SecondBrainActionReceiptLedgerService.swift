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
    var action: String?
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
        action: String? = nil,
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
        self.action = action
        self.actor = actor
        self.status = status
        self.sourceRef = sourceRef
        self.evidenceRef = evidenceRef
        self.since = since
        self.before = before
        self.limit = max(1, min(limit, 100))
    }
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
        if let action = filter.action {
            clauses.append("action = ?")
            bindings.append(action)
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
        return records
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
