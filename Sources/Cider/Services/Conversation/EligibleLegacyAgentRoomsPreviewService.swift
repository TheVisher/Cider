import Foundation

/// Presentation-only adapter for CID-796. It is intentionally absent from production composition.
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
        guard preview.readOnly, !preview.changed, !preview.safeForBackfill, !preview.safeForShadowWrites,
              preview.counts.isExact else { return blocked() }
        switch preview.state {
        case .empty:
            return .empty(authority: .legacyAuthoritativePreview)
        case .blocked:
            return blocked()
        case .failed:
            return .failed(authority: .legacyAuthoritativePreview, message: Self.failedMessage)
        case .eligibleEmpty:
            let notice = makeNotice(preview.counts, kind: .empty)
            return .eligibleEmpty(authority: .legacyAuthoritativePreview, notice: notice)
        case .ready:
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
        .blocked(authority: .legacyAuthoritativePreview, message: Self.blockedMessage)
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
