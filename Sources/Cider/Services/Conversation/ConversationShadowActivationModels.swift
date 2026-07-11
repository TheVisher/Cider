import CryptoKit
import Foundation
import os

struct ConversationShadowSemanticFingerprint: Codable, Equatable, Sendable {
    static let formatVersion = "cider.conversation-shadow-semantic.v1"

    let version: String
    let planFingerprint: String
    let roomIdentityFingerprint: String
    let roomUpdatedAt: Date
    let bindingCount: Int
    let bindingIdentityHighWater: String
    let bindingCursorMessageIDHighWater: String?
    let bindingCursorTimestampHighWater: Date?
    let turnCount: Int
    let turnHighWater: String
    let messageCount: Int
    let messageHighWater: String
    let terminalSource: ConversationSourceIdentity?
}

struct ConversationShadowSemanticFingerprintBuilder {
    func make(_ plan: LegacyConversationImportPlan) -> ConversationShadowSemanticFingerprint {
        let room = plan.rooms[0]
        let bindingHashes = plan.bindings.map(bindingIdentityHash)
        let turnHashes = plan.turns.map(turnHash)
        let messageHashes = plan.messages.map(messageHash)
        let terminalSource = plan.messages.last?.source
        let planFingerprint = hash([
            roomHash(room),
            cumulative(plan.bindings.map(bindingHash)),
            cumulative(turnHashes),
            cumulative(messageHashes),
        ])
        return .init(
            version: Self.semanticVersion,
            planFingerprint: planFingerprint,
            roomIdentityFingerprint: roomIdentityHash(room),
            roomUpdatedAt: room.updatedAt,
            bindingCount: plan.bindings.count,
            bindingIdentityHighWater: cumulative(bindingHashes),
            bindingCursorMessageIDHighWater: plan.bindings.first(where: { $0.state == .active })?.cursorMessageID,
            bindingCursorTimestampHighWater: plan.bindings.compactMap(\.cursorTimestamp).max(),
            turnCount: plan.turns.count,
            turnHighWater: cumulative(turnHashes),
            messageCount: plan.messages.count,
            messageHighWater: cumulative(messageHashes),
            terminalSource: terminalSource
        )
    }

    func provesPrefix(
        _ older: ConversationShadowSemanticFingerprint,
        isRepresentedBy newerPlan: LegacyConversationImportPlan
    ) -> Bool {
        guard older.version == Self.semanticVersion,
              newerPlan.rooms.count == 1,
              let room = newerPlan.rooms.first,
              older.roomIdentityFingerprint == roomIdentityHash(room),
              older.roomUpdatedAt <= room.updatedAt,
              older.bindingCount <= newerPlan.bindings.count,
              older.turnCount <= newerPlan.turns.count,
              older.messageCount <= newerPlan.messages.count,
              older.bindingIdentityHighWater == cumulative(
                  newerPlan.bindings.prefix(older.bindingCount).map(bindingIdentityHash)
              ),
              older.turnHighWater == cumulative(newerPlan.turns.prefix(older.turnCount).map(turnHash)),
              older.messageHighWater == cumulative(newerPlan.messages.prefix(older.messageCount).map(messageHash))
        else { return false }
        if let olderCursor = older.bindingCursorTimestampHighWater {
            guard let newerCursor = newerPlan.bindings.compactMap(\.cursorTimestamp).max(),
                  newerCursor >= olderCursor else { return false }
        }
        let newerCursorID = newerPlan.bindings.first(where: { $0.state == .active })?.cursorMessageID
        if let olderCursorID = older.bindingCursorMessageIDHighWater,
           olderCursorID != newerCursorID,
           (older.bindingCursorTimestampHighWater == nil ||
            newerPlan.bindings.compactMap(\.cursorTimestamp).max() == nil) {
            return false
        }
        return true
    }

    private static let semanticVersion = ConversationShadowSemanticFingerprint.formatVersion

    private func roomIdentityHash(_ room: LegacyConversationRoomPlanRecord) -> String {
        hash([room.id.uuidString, room.stableKey, room.kind, date(room.createdAt)])
    }

    private func roomHash(_ room: LegacyConversationRoomPlanRecord) -> String {
        hash([
            roomIdentityHash(room), room.title, room.lifecycleState.rawValue,
            dictionary(room.metadata), date(room.updatedAt), optionalDate(room.archivedAt),
            String(room.nextTurnSequence), String(room.nextMessageSequence),
        ])
    }

    private func bindingIdentityHash(_ binding: LegacyConversationBindingPlanRecord) -> String {
        hash([
            binding.id.uuidString, binding.roomID.uuidString,
            binding.parentBindingID?.uuidString ?? "", binding.runtimeID,
            binding.transportID, binding.sourceNamespace,
            binding.externalSessionID, date(binding.createdAt),
        ])
    }

    private func bindingHash(_ binding: LegacyConversationBindingPlanRecord) -> String {
        hash([
            bindingIdentityHash(binding), binding.state.rawValue,
            binding.cursorMessageID ?? "", optionalDate(binding.cursorTimestamp),
            dictionary(binding.metadata), date(binding.updatedAt),
        ])
    }

    private func turnHash(_ turn: LegacyConversationTurnPlanRecord) -> String {
        hash([
            turn.id.uuidString, turn.roomID.uuidString, String(turn.sequence),
            turn.runtimeBindingID?.uuidString ?? "", source(turn.source),
            turn.status.rawValue, dictionary(turn.metadata), date(turn.createdAt),
            optionalDate(turn.startedAt), optionalDate(turn.completedAt), date(turn.updatedAt),
        ])
    }

    private func messageHash(_ message: LegacyConversationMessagePlanRecord) -> String {
        hash([
            message.id.uuidString, message.roomID.uuidString,
            message.turnID?.uuidString ?? "", message.runtimeBindingID?.uuidString ?? "",
            message.parentMessageID?.uuidString ?? "", String(message.sequence),
            message.role, message.contentText, message.status.rawValue,
            message.finishReason?.rawValue ?? "", source(message.source),
            optionalDate(message.sourceCreatedAt), dictionary(message.metadata),
            date(message.createdAt), date(message.updatedAt),
        ])
    }

    private func cumulative<S: Sequence>(_ values: S) -> String where S.Element == String {
        values.reduce(hash([])) { hash([$0, $1]) }
    }

    private func source(_ value: ConversationSourceIdentity?) -> String {
        guard let value else { return "" }
        return hash([value.namespace, value.id])
    }

    private func dictionary(_ value: [String: String]) -> String {
        hash(value.keys.sorted().flatMap { [$0, value[$0] ?? ""] })
    }

    private func date(_ value: Date) -> String {
        String(value.timeIntervalSince1970.bitPattern, radix: 16)
    }

    private func optionalDate(_ value: Date?) -> String {
        value.map(date) ?? ""
    }

    private func hash(_ values: [String]) -> String {
        var data = Data()
        for value in values {
            let bytes = Data(value.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(bytes)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ConversationCompletedSnapshotProvenance: Equatable, Sendable {
    case hermesRunsAPI
    case hermesStreamingOrDelta
    case commandLineOrExportMerge
    case other
}

enum ConversationCompletedSnapshotRunState: Equatable, Sendable {
    case completed
    case pending
    case failed
    case cancelled
}

struct ConversationCompletedSnapshotEligibility: Equatable, Sendable {
    let provenance: ConversationCompletedSnapshotProvenance
    let runState: ConversationCompletedSnapshotRunState
    let containsTools: Bool
    let containsReasoning: Bool
    let containsApproval: Bool
    let sessionSyncComplete: Bool

    var isEligible: Bool {
        provenance == .hermesRunsAPI && runState == .completed &&
        !containsTools && !containsReasoning && !containsApproval && sessionSyncComplete
    }
}

struct ConversationShadowActivationReceipt: Equatable, Sendable {
    let generationID: UUID
    let conversationID: UUID
    let registryCommitted: Bool
    let jsonlStatus: LegacyConversationWriteStatus
    let shadowCorrelationID: UUID?
    let shadowStatus: ConversationShadowHealthStatus?
    let shadowCode: ConversationShadowDiagnosticCode?
    let planFingerprint: String?
    let messageCount: Int
    let terminalSourceNamespace: String?
    let terminalSourceID: String?
}

enum ConversationShadowLogSeverity: Equatable, Sendable {
    case info
    case error
    case fault
}

enum ConversationShadowStartupFailureCode: String, Equatable, Sendable {
    case databaseClosed = "database_closed"
    case healthInitializationFailed = "health_initialization_failed"
    case viewModelBootstrapUnavailable = "view_model_bootstrap_unavailable"
}

struct ConversationShadowLogEvent: Equatable, Sendable {
    let severity: ConversationShadowLogSeverity
    let generationID: String?
    let conversationID: String?
    let correlationID: String?
    let registryStatus: String?
    let primaryStatus: String?
    let shadowStatus: String?
    let code: String?
    let planFingerprint: String?
    let messageCount: Int?
    let terminalSourceNamespace: String?
    let terminalSourceID: String?

    static func receipt(_ receipt: ConversationShadowActivationReceipt) -> Self {
        Self(
            severity: severity(for: receipt),
            generationID: receipt.generationID.uuidString,
            conversationID: receipt.conversationID.uuidString,
            correlationID: receipt.shadowCorrelationID?.uuidString,
            registryStatus: receipt.registryCommitted ? "committed" : "failed",
            primaryStatus: receipt.jsonlStatus.rawValue,
            shadowStatus: receipt.shadowStatus?.rawValue,
            code: receipt.shadowCode?.rawValue,
            planFingerprint: receipt.planFingerprint.map(bounded),
            messageCount: receipt.messageCount,
            terminalSourceNamespace: receipt.terminalSourceNamespace.map(bounded),
            terminalSourceID: receipt.terminalSourceID.map(bounded)
        )
    }

    static func startupFailure(_ code: ConversationShadowStartupFailureCode) -> Self {
        Self(
            severity: .fault,
            generationID: nil,
            conversationID: nil,
            correlationID: nil,
            registryStatus: nil,
            primaryStatus: nil,
            shadowStatus: nil,
            code: code.rawValue,
            planFingerprint: nil,
            messageCount: nil,
            terminalSourceNamespace: nil,
            terminalSourceID: nil
        )
    }

    var boundedFields: [String] {
        [
            generationID,
            conversationID,
            correlationID,
            registryStatus,
            primaryStatus,
            shadowStatus,
            code,
            planFingerprint,
            messageCount.map(String.init),
            terminalSourceNamespace,
            terminalSourceID,
        ].compactMap { $0 }
    }

    var logLine: String {
        [
            "generation_id=\(generationID ?? "none")",
            "conversation_id=\(conversationID ?? "none")",
            "correlation_id=\(correlationID ?? "none")",
            "registry_status=\(registryStatus ?? "none")",
            "primary_status=\(primaryStatus ?? "none")",
            "shadow_status=\(shadowStatus ?? "none")",
            "code=\(code ?? "none")",
            "plan_fingerprint=\(planFingerprint ?? "none")",
            "message_count=\(messageCount.map(String.init) ?? "none")",
            "terminal_source_namespace=\(terminalSourceNamespace ?? "none")",
            "terminal_source_id=\(terminalSourceID ?? "none")",
        ].joined(separator: " ")
    }

    private static func severity(
        for receipt: ConversationShadowActivationReceipt
    ) -> ConversationShadowLogSeverity {
        if receipt.shadowCode == .diagnosticStoreSaturated ||
            receipt.shadowStatus == .outcomeUnknown ||
            receipt.shadowStatus == .reserved {
            return .fault
        }
        if !receipt.registryCommitted ||
            receipt.jsonlStatus == .failed ||
            receipt.shadowStatus == .repairNeeded ||
            receipt.shadowCode != nil {
            return .error
        }
        return .info
    }

    private static func bounded(_ value: String) -> String {
        String(value.prefix(ConversationShadowActivationReceiptReporter.maximumIdentityCharacters))
    }
}

@MainActor
final class ConversationShadowRuntimeLogger {
    private let sink: (ConversationShadowLogEvent) -> Void

    init(sink: @escaping (ConversationShadowLogEvent) -> Void) {
        self.sink = sink
    }

    static func production(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.cider.app"
    ) -> ConversationShadowRuntimeLogger {
        let logger = Logger(subsystem: subsystem, category: "ConversationShadow")
        return ConversationShadowRuntimeLogger { event in
            switch event.severity {
            case .info:
                logger.info("\(event.logLine, privacy: .public)")
            case .error:
                logger.error("\(event.logLine, privacy: .public)")
            case .fault:
                logger.fault("\(event.logLine, privacy: .public)")
            }
        }
    }

    func logReceipt(_ receipt: ConversationShadowActivationReceipt) {
        sink(.receipt(receipt))
    }

    func logStartupFailure(_ code: ConversationShadowStartupFailureCode) {
        sink(.startupFailure(code))
    }
}

@MainActor
final class ConversationShadowActivationReceiptReporter {
    nonisolated static let maximumReceipts = 100
    nonisolated static let maximumIdentityCharacters = 256

    private let maximumRecords: Int
    private let runtimeLogger: ConversationShadowRuntimeLogger?
    private(set) var receipts: [ConversationShadowActivationReceipt] = []
    private(set) var droppedCount = 0

    init(
        maximumRecords: Int = maximumReceipts,
        runtimeLogger: ConversationShadowRuntimeLogger? = nil
    ) {
        self.maximumRecords = max(0, min(maximumRecords, Self.maximumReceipts))
        self.runtimeLogger = runtimeLogger
    }

    func report(_ receipt: ConversationShadowActivationReceipt) {
        let bounded = ConversationShadowActivationReceipt(
            generationID: receipt.generationID,
            conversationID: receipt.conversationID,
            registryCommitted: receipt.registryCommitted,
            jsonlStatus: receipt.jsonlStatus,
            shadowCorrelationID: receipt.shadowCorrelationID,
            shadowStatus: receipt.shadowStatus,
            shadowCode: receipt.shadowCode,
            planFingerprint: receipt.planFingerprint.map(Self.bounded),
            messageCount: receipt.messageCount,
            terminalSourceNamespace: receipt.terminalSourceNamespace.map(Self.bounded),
            terminalSourceID: receipt.terminalSourceID.map(Self.bounded)
        )
        runtimeLogger?.logReceipt(bounded)
        guard maximumRecords > 0 else {
            droppedCount += 1
            return
        }
        if receipts.count == maximumRecords {
            receipts.removeFirst()
            droppedCount += 1
        }
        receipts.append(bounded)
    }

    private static func bounded(_ value: String) -> String {
        String(value.prefix(maximumIdentityCharacters))
    }
}
