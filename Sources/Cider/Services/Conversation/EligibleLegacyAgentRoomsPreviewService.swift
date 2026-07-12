import Foundation

/// Read-only presentation adapter for independently eligible legacy Rooms previews.
@MainActor
final class EligibleLegacyAgentRoomsPreviewService {
    static let blockedMessage = "We couldn’t establish a complete, conflict-free read-only view. No legacy rooms are shown."
    static let failedMessage = "No legacy rooms are shown. Try again."

    private let loadPreview: () -> LegacyConversationEligiblePreview
    private let now: () -> Date

    init(
        loadPreview: @escaping () -> LegacyConversationEligiblePreview,
        now: @escaping () -> Date = Date.init
    ) {
        self.loadPreview = loadPreview
        self.now = now
    }

    func loadWorkspace() -> AgentRoomsWorkspaceState {
        let preview = loadPreview()
        guard preview.formatVersion == LegacyConversationEligiblePreview.currentFormatVersion,
              preview.readOnly, !preview.changed, !preview.safeForBackfill, !preview.safeForShadowWrites,
              preview.counts.isExact else { return blocked() }
        switch preview.state {
        case .empty:
            guard preview.conflictDiagnosis == nil, preview.registryMappingDiagnosis == nil else { return blocked() }
            return .empty(authority: .legacyAuthoritativePreview)
        case .blocked:
            if let diagnosis = preview.registryMappingDiagnosis {
                guard preview.conflictDiagnosis == nil else { return blocked() }
                return registryMappingConflict(preview: preview, diagnosis: diagnosis)
            }
            guard let diagnosis = preview.conflictDiagnosis, preview.registryMappingDiagnosis == nil else { return blocked() }
            return identityConflict(preview: preview, diagnosis: diagnosis)
        case .failed:
            guard preview.conflictDiagnosis == nil, preview.registryMappingDiagnosis == nil else { return blocked() }
            return .failed(authority: .legacyAuthoritativePreview, message: Self.failedMessage)
        case .eligibleEmpty:
            guard preview.conflictDiagnosis == nil, preview.registryMappingDiagnosis == nil else { return blocked() }
            let notice = makeNotice(preview.counts, kind: .empty)
            return .eligibleEmpty(authority: .legacyAuthoritativePreview, notice: notice)
        case .ready:
            guard preview.conflictDiagnosis == nil, preview.registryMappingDiagnosis == nil else { return blocked() }
            guard preview.rooms.count == preview.counts.displayedTotal else { return blocked() }
            let rooms = preview.rooms.compactMap(mapRoom)
            guard rooms.count == preview.rooms.count, let first = rooms.first else { return blocked() }
            let notice = makeNotice(preview.counts, kind: .loaded)
            return .eligibleLoaded(
                authority: .legacyAuthoritativePreview,
                rooms: rooms,
                selectedRoomID: first.id,
                notice: notice
            )
        }
    }

    private func registryMappingConflict(
        preview: LegacyConversationEligiblePreview,
        diagnosis: LegacyRegistryMappingDiagnosis
    ) -> AgentRoomsWorkspaceState {
        guard diagnosis.isValid, preview.counts == .zero, preview.rooms.isEmpty else { return blocked() }
        let rows = diagnosis.counts.compactMap { count -> AgentRoomsRegistryMappingNotice.Row? in
            guard !count.conflictingMappingGroups.isZero else { return nil }
            let label: String
            switch count.kind {
            case .conversationIdentityMapping: label = "Conversation mappings"
            case .stableRoomMapping: label = "Stable room mappings"
            }
            return .init(label: label, count: count.conflictingMappingGroups.displayValue)
        }
        guard !rows.isEmpty else { return blocked() }
        return .legacyRegistryMappingConflict(
            authority: .legacyAuthoritativePreview,
            notice: .init(rows: rows, affectedRegistryRecordCount: diagnosis.affectedRegistryRecordCount.displayValue)
        )
    }

    private func identityConflict(
        preview: LegacyConversationEligiblePreview,
        diagnosis: LegacyCandidateConflictDiagnosis
    ) -> AgentRoomsWorkspaceState {
        guard diagnosis.isValid, preview.counts == .zero, preview.rooms.isEmpty else { return blocked() }
        let rows = diagnosis.counts.compactMap { count -> AgentRoomsIdentityConflictNotice.Row? in
            guard !count.conflictingIdentityGroups.isZero else { return nil }
            let label: String
            switch count.kind {
            case .messageRecordIdentity: label = "Message record ID conflicts"
            case .messageProvenanceIdentity: label = "Message provenance conflicts"
            case .runtimeBindingIdentity: label = "Runtime binding conflicts"
            case .historicalTurnProvenanceIdentity: label = "Historical turn provenance conflicts"
            }
            return .init(label: label, count: count.conflictingIdentityGroups.displayValue)
        }
        guard !rows.isEmpty else { return blocked() }
        return .legacyIdentityConflict(
            authority: .legacyAuthoritativePreview,
            notice: .init(
                rows: rows,
                affectedCandidateCount: diagnosis.affectedCandidateCount.displayValue
            )
        )
    }

    private func makeNotice(_ counts: LegacyConversationEligibleCounts, kind: AgentRoomsEligibleNotice.Kind) -> AgentRoomsEligibleNotice {
        .init(
            kind: kind,
            displayed: counts.displayedTotal,
            omitted: counts.roomLocalOmitted,
            capOmitted: counts.eligibleCapOmitted,
            unregistered: counts.unregisteredFileTotal
        )
    }

    private func mapRoom(_ eligible: LegacyConversationEligibleRoom) -> AgentRoom? {
        guard eligible.plan.rooms.count == 1, let room = eligible.plan.rooms.first,
              eligible.totalMessages == eligible.plan.messages.count + eligible.messageCapOmitted,
              eligible.messageCapOmitted == max(eligible.totalMessages - 100, 0) else { return nil }
        let bindings = eligible.plan.bindings.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
        let binding = bindings.first(where: { $0.state == .active }) ?? bindings.first
        let runtime = displayRuntime(binding?.runtimeID)
        let messages = eligible.plan.messages.map { message -> AgentRoomMessage in
            if message.role == "user" {
                return .init(id: message.id.uuidString, role: .human, author: "You", body: message.contentText)
            }
            return .init(id: message.id.uuidString, role: .agent, author: runtime, body: message.contentText)
        }
        let preview = messages.reversed().lazy.map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? LegacyAgentRoomsPreviewService.fallbackPreview
        let title = room.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentRoom(
            id: room.id.uuidString,
            title: title.isEmpty ? "Untitled Room" : title,
            preview: preview,
            updatedAt: room.updatedAt,
            relativeTime: relativeTime(room.updatedAt),
            transcript: .init(runtimeLabel: runtime, messages: messages, link: nil, receipt: nil, futureArtifact: nil),
            messageLimitNotice: eligible.messageCapOmitted > 0 ? "Showing the newest 100 of \(eligible.totalMessages) messages." : nil
        )
    }

    private func blocked() -> AgentRoomsWorkspaceState {
        .eligiblePreviewBlocked(authority: .legacyAuthoritativePreview)
    }

    private func displayRuntime(_ runtimeID: String?) -> String {
        switch runtimeID?.lowercased() {
        case "hermes": "Hermes"
        case "codex": "Codex"
        case "cider-cli": "Cider CLI"
        default: "Legacy runtime"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = max(0, now().timeIntervalSince(date))
        if interval < 60 { return "Now" }
        if interval < 3_600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h" }
        if interval < 172_800 { return "Yesterday" }
        return "\(Int(interval / 86_400))d"
    }
}
