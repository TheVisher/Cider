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
    let relativeTime: String
    let transcript: AgentRoomTranscript
}

enum AgentRoomsWorkspaceState: Equatable, Sendable {
    case loading
    case empty
    case failed(message: String)
    case loaded(rooms: [AgentRoom], selectedRoomID: String)

    func projection(selectedRoomID localSelection: String? = nil) -> AgentRoomsWorkspaceProjection {
        switch self {
        case .loading:
            return .loading
        case .empty:
            return .empty
        case .failed(let message):
            return .failed(message: message)
        case .loaded(let rooms, let storedSelection):
            guard let firstRoom = rooms.first else { return .empty }
            let requestedSelection = localSelection ?? storedSelection
            let selectedRoom = rooms.first(where: { $0.id == requestedSelection }) ?? firstRoom
            return .loaded(rooms: rooms, selectedRoom: selectedRoom)
        }
    }
}

enum AgentRoomsWorkspaceProjection: Equatable, Sendable {
    case loading
    case empty
    case failed(message: String)
    case loaded(rooms: [AgentRoom], selectedRoom: AgentRoom)
}

enum AgentRoomsFixtureProvider {
    static let workspaceState = AgentRoomsWorkspaceState.loaded(
        rooms: [ciderProduct, weeklyReview, captureQuality],
        selectedRoomID: ciderProduct.id
    )

    private static let ciderProduct = AgentRoom(
        id: "cider-product",
        title: "Cider Product",
        preview: "The first native Rooms slice is ready to inspect.",
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
