import Foundation

@MainActor
protocol AgentRoomsActionServicing: AnyObject {
    func createConversation() throws -> ConversationRoom
    func createConversation(title: String) throws -> ConversationRoom
    func renameConversation(id: UUID, title: String) throws -> ConversationRoom
    func archiveConversation(id: UUID) throws -> ConversationRoom
    func restoreConversation(id: UUID) throws -> ConversationRoom
}

/// Provider-neutral room mutations over Cider's canonical Conversation Core.
@MainActor
final class AgentRoomsActionService: AgentRoomsActionServicing {
    static let defaultTitle = "New Conversation"
    static let maximumTitleLength = 120

    private let repository: ConversationRepository
    private let now: () -> Date

    init(repository: ConversationRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    func createConversation(title: String = AgentRoomsActionService.defaultTitle) throws -> ConversationRoom {
        let timestamp = now()
        return try repository.createRoom(.init(
            title: try normalizedTitle(title),
            createdAt: timestamp,
            updatedAt: timestamp
        ))
    }

    func createConversation() throws -> ConversationRoom {
        try createConversation(title: Self.defaultTitle)
    }

    func renameConversation(id: UUID, title: String) throws -> ConversationRoom {
        try requireUserManageableRoom(id: id)
        return try repository.renameRoom(roomID: id, title: normalizedTitle(title), at: now())
    }

    func archiveConversation(id: UUID) throws -> ConversationRoom {
        try requireUserManageableRoom(id: id)
        return try setLifecycle(id: id, state: .archived)
    }

    func restoreConversation(id: UUID) throws -> ConversationRoom {
        try requireUserManageableRoom(id: id)
        return try setLifecycle(id: id, state: .active)
    }

    private func requireUserManageableRoom(id: UUID) throws {
        guard let room = try repository.room(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation room was not found.")
        }
        guard room.stableKey != AgentRoomsTestChatPersistence.stableRoomKey else {
            throw ConversationRepositoryError.invalidDraft("Cider Test Chat keeps its reserved identity and title.")
        }
    }

    private func setLifecycle(id: UUID, state: ConversationRoomLifecycle) throws -> ConversationRoom {
        try repository.setLifecycle(roomID: id, state: state, at: now())
        guard let room = try repository.room(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation room was not found after lifecycle update.")
        }
        return room
    }

    private func normalizedTitle(_ raw: String) throws -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let normalized = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else {
            throw ConversationRepositoryError.invalidDraft("Conversation title must not be empty.")
        }
        return String(normalized.prefix(Self.maximumTitleLength))
    }
}
