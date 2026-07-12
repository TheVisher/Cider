import Foundation

enum AgentRoomMessageRole: String, Equatable, Sendable {
    case human
    case agent
}

struct AgentRoomMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: AgentRoomMessageRole
    let author: String
    let body: String
}

struct AgentRoomLink: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
}

enum AgentRoomReceiptStatus: String, Equatable, Sendable {
    case completed
    case failed
    case cancelled
}

struct AgentRoomReceipt: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let status: AgentRoomReceiptStatus
}

struct AgentRoomFutureArtifact: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct AgentRoomTranscript: Equatable, Sendable {
    let runtimeLabel: String
    let messages: [AgentRoomMessage]
    let link: AgentRoomLink?
    let receipt: AgentRoomReceipt?
    let futureArtifact: AgentRoomFutureArtifact?
}

struct AgentRoom: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let preview: String
    let updatedAt: Date
    let relativeTime: String
    let transcript: AgentRoomTranscript
    var messageLimitNotice: String? = nil
}

struct AgentRoomsEligibleNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case loaded, empty }

    let kind: Kind
    let displayed: Int
    let omitted: Int
    let capOmitted: Int
    let unregistered: Int

    private func bounded(_ value: Int) -> String { value > 99 ? "99+" : String(max(0, value)) }

    var title: String { kind == .loaded ? "Eligible legacy preview" : "No eligible legacy rooms" }

    var detail: String {
        switch kind {
        case .loaded:
            return "Showing \(bounded(displayed)) independently validated room(s). \(bounded(omitted)) registered room(s) were omitted after validation. \(bounded(capOmitted)) additional eligible room(s) are not shown by the 20-room limit. \(bounded(unregistered)) unregistered conversation file(s) were excluded. Read-only, noncanonical legacy history. Nothing has been imported or changed."
        case .empty:
            return "No independently validated rooms can be shown. \(bounded(omitted)) registered room(s) were omitted after validation, and \(bounded(unregistered)) unregistered conversation file(s) were excluded. Nothing has been imported or changed."
        }
    }

    var accessibilityLabel: String {
        "\(title). \(detail) Read-only, legacy authoritative, noncanonical preview, not imported. Messaging disabled."
    }
}

struct AgentRoomsIdentityConflictNotice: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let label: String
        let count: String
    }

    let rows: [Row]
    let affectedCandidateCount: String

    let title = "Legacy Rooms have an identity conflict"
    let detail = "Multiple registered rooms claim the same message or runtime identity. To avoid showing history under the wrong room, Cider is showing no rooms. Nothing was imported or changed."

    var accessibilityLabel: String {
        let categorySummary = rows.map { "\($0.label): \($0.count)." }.joined(separator: " ")
        return "\(title). \(detail) \(categorySummary) Affected registered rooms: \(affectedCandidateCount). Read-only, legacy authoritative, noncanonical preview. No rooms shown. Nothing imported or changed. Messaging disabled."
    }
}

enum AgentRoomsWorkspaceAuthority: String, Equatable, Sendable {
    case canonicalIncomplete
    case legacyAuthoritativePreview
}

enum AgentRoomsWorkspaceState: Equatable, Sendable {
    case loading(authority: AgentRoomsWorkspaceAuthority)
    case empty(authority: AgentRoomsWorkspaceAuthority)
    case blocked(authority: AgentRoomsWorkspaceAuthority, message: String)
    case eligiblePreviewBlocked(authority: AgentRoomsWorkspaceAuthority)
    case legacyIdentityConflict(authority: AgentRoomsWorkspaceAuthority, notice: AgentRoomsIdentityConflictNotice)
    case failed(authority: AgentRoomsWorkspaceAuthority, message: String)
    case loaded(authority: AgentRoomsWorkspaceAuthority, rooms: [AgentRoom], selectedRoomID: String)
    case eligibleEmpty(authority: AgentRoomsWorkspaceAuthority, notice: AgentRoomsEligibleNotice)
    case eligibleLoaded(authority: AgentRoomsWorkspaceAuthority, rooms: [AgentRoom], selectedRoomID: String, notice: AgentRoomsEligibleNotice)

    var authority: AgentRoomsWorkspaceAuthority {
        switch self {
        case .loading(let authority), .empty(let authority):
            return authority
        case .blocked(let authority, _), .failed(let authority, _), .loaded(let authority, _, _),
             .eligibleEmpty(let authority, _), .eligibleLoaded(let authority, _, _, _):
            return authority
        case .eligiblePreviewBlocked(let authority), .legacyIdentityConflict(let authority, _):
            return authority
        }
    }

    func projection(selectedRoomID localSelection: String? = nil) -> AgentRoomsWorkspaceProjection {
        switch self {
        case .loading(let authority):
            return .loading(authority: authority)
        case .empty(let authority):
            return .empty(authority: authority)
        case .blocked(let authority, let message):
            return .blocked(authority: authority, message: message)
        case .eligiblePreviewBlocked(let authority):
            return .eligiblePreviewBlocked(authority: authority)
        case .legacyIdentityConflict(let authority, let notice):
            return .legacyIdentityConflict(authority: authority, notice: notice)
        case .failed(let authority, let message):
            return .failed(authority: authority, message: message)
        case .loaded(let authority, let rooms, let storedSelection):
            guard let firstRoom = rooms.first else { return .empty(authority: authority) }
            let requestedSelection = localSelection ?? storedSelection
            let selectedRoom = rooms.first(where: { $0.id == requestedSelection }) ?? firstRoom
            return .loaded(authority: authority, rooms: rooms, selectedRoom: selectedRoom)
        case .eligibleEmpty(let authority, let notice):
            return .eligibleEmpty(authority: authority, notice: notice)
        case .eligibleLoaded(let authority, let rooms, let storedSelection, let notice):
            guard let firstRoom = rooms.first else { return .eligibleEmpty(authority: authority, notice: notice) }
            let requestedSelection = localSelection ?? storedSelection
            let selectedRoom = rooms.first(where: { $0.id == requestedSelection }) ?? firstRoom
            return .eligibleLoaded(authority: authority, rooms: rooms, selectedRoom: selectedRoom, notice: notice)
        }
    }
}

enum AgentRoomsWorkspaceProjection: Equatable, Sendable {
    case loading(authority: AgentRoomsWorkspaceAuthority)
    case empty(authority: AgentRoomsWorkspaceAuthority)
    case blocked(authority: AgentRoomsWorkspaceAuthority, message: String)
    case eligiblePreviewBlocked(authority: AgentRoomsWorkspaceAuthority)
    case legacyIdentityConflict(authority: AgentRoomsWorkspaceAuthority, notice: AgentRoomsIdentityConflictNotice)
    case failed(authority: AgentRoomsWorkspaceAuthority, message: String)
    case loaded(authority: AgentRoomsWorkspaceAuthority, rooms: [AgentRoom], selectedRoom: AgentRoom)
    case eligibleEmpty(authority: AgentRoomsWorkspaceAuthority, notice: AgentRoomsEligibleNotice)
    case eligibleLoaded(authority: AgentRoomsWorkspaceAuthority, rooms: [AgentRoom], selectedRoom: AgentRoom, notice: AgentRoomsEligibleNotice)
}

enum AgentRoomsFixtureProvider {
    static let workspaceState = AgentRoomsWorkspaceState.loaded(
        authority: .canonicalIncomplete,
        rooms: [ciderProduct, weeklyReview, captureQuality],
        selectedRoomID: ciderProduct.id
    )

    private static let ciderProduct = AgentRoom(
        id: "cider-product",
        title: "Cider Product",
        preview: "The first native Rooms slice is ready to inspect.",
        updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
        relativeTime: "Now",
        transcript: AgentRoomTranscript(
            runtimeLabel: "Hermes",
            messages: [
                AgentRoomMessage(
                    id: "cider-product-message-1",
                    role: .human,
                    author: "You",
                    body: "Give Rooms a native home without turning on production conversation data."
                ),
                AgentRoomMessage(
                    id: "cider-product-message-2",
                    role: .agent,
                    author: "Hermes",
                    body: "I kept this thread fixture-backed and read-only. The live assistant remains a separate panel."
                ),
                AgentRoomMessage(
                    id: "cider-product-message-3",
                    role: .human,
                    author: "You",
                    body: "Make durable work feel tangible: context, activity, and the next artifact."
                ),
                AgentRoomMessage(
                    id: "cider-product-message-4",
                    role: .agent,
                    author: "Hermes",
                    body: "This preview now carries a project link and a completed receipt, while future artifacts stay clearly inactive."
                ),
            ],
            link: AgentRoomLink(
                id: "cider-project-link",
                title: "Cider",
                subtitle: "Project"
            ),
            receipt: AgentRoomReceipt(
                id: "cid-786-receipt",
                title: "Reviewed CID-786",
                detail: "Native Rooms slice selected",
                status: .completed
            ),
            futureArtifact: AgentRoomFutureArtifact(
                id: "rooms-artifact-placeholder",
                title: "Room artifact",
                detail: "Artifacts will appear here in a future slice."
            )
        )
    )

    private static let weeklyReview = AgentRoom(
        id: "weekly-review",
        title: "Weekly Review",
        preview: "A durable thread for decisions that should survive the week.",
        updatedAt: Date(timeIntervalSince1970: 1_749_992_800),
        relativeTime: "2h",
        transcript: AgentRoomTranscript(
            runtimeLabel: "Hermes",
            messages: [
                AgentRoomMessage(
                    id: "weekly-review-message-1",
                    role: .human,
                    author: "You",
                    body: "Keep the review focused on decisions and open loops."
                ),
                AgentRoomMessage(
                    id: "weekly-review-message-2",
                    role: .agent,
                    author: "Hermes",
                    body: "Three decisions are stable. Two open loops remain for the next review."
                ),
            ],
            link: nil,
            receipt: nil,
            futureArtifact: nil
        )
    )

    private static let captureQuality = AgentRoom(
        id: "capture-quality",
        title: "Capture Quality",
        preview: "Checking whether saves keep their useful provenance.",
        updatedAt: Date(timeIntervalSince1970: 1_749_913_600),
        relativeTime: "Yesterday",
        transcript: AgentRoomTranscript(
            runtimeLabel: "Hermes",
            messages: [
                AgentRoomMessage(
                    id: "capture-quality-message-1",
                    role: .human,
                    author: "You",
                    body: "Are recent captures preserving enough context to trust later?"
                ),
                AgentRoomMessage(
                    id: "capture-quality-message-2",
                    role: .agent,
                    author: "Hermes",
                    body: "The sampled captures retain source and routing context. The remaining uncertainty is visible for review."
                ),
            ],
            link: nil,
            receipt: nil,
            futureArtifact: nil
        )
    )
}
