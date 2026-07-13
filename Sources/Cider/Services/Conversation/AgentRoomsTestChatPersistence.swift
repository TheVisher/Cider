import Foundation

struct AgentRoomsTestChatSnapshot: Sendable {
    let roomID: UUID
    let conversationState: HermesConversationState
    let messages: [AIAssistantMessage]
    let latestRunID: String
    let latestCiderReferences: [HermesCiderReference]
}

enum AgentRoomsTestChatPersistenceError: Error, Equatable {
    case ineligibleCompletion
    case authorityMismatch
    case corruptHistory
}

/// Backward-compatible façade for the reserved Test Chat. Production Test Chat and
/// ordinary canonical rooms both use `AgentRoomsConversationPersistence`.
@MainActor
final class AgentRoomsTestChatPersistence {
    static let stableRoomKey = "cider.rooms.test-chat.v1"

    let database: CiderDatabase
    let repository: ConversationRepository

    init(database: CiderDatabase = .shared, repository: ConversationRepository? = nil) {
        self.database = database
        self.repository = repository ?? ConversationRepository(database: database)
    }

    func persist(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        expectedConversationID: UUID
    ) throws {
        do {
            try conversationPersistence.persistCompletedReservedTestChat(
                completion,
                expectedText: expectedText,
                expectedConversationID: expectedConversationID
            )
        } catch AgentRoomsConversationPersistenceError.ineligibleCompletion {
            throw AgentRoomsTestChatPersistenceError.ineligibleCompletion
        } catch AgentRoomsConversationPersistenceError.ineligibleRoom,
                AgentRoomsConversationPersistenceError.authorityMismatch {
            throw AgentRoomsTestChatPersistenceError.authorityMismatch
        } catch {
            throw AgentRoomsTestChatPersistenceError.corruptHistory
        }
    }

    func restore() throws -> AgentRoomsTestChatSnapshot? {
        do {
            guard let snapshot = try conversationPersistence.restoreReservedTestChat() else { return nil }
            guard snapshot.latestTurnStatus == .completed,
                  let latestRunID = snapshot.latestRunID,
                  !snapshot.transportMessages.isEmpty
            else { throw AgentRoomsTestChatPersistenceError.corruptHistory }
            return AgentRoomsTestChatSnapshot(
                roomID: snapshot.room.id,
                conversationState: snapshot.conversationState,
                messages: snapshot.transportMessages,
                latestRunID: latestRunID,
                latestCiderReferences: snapshot.latestCiderReferences
            )
        } catch let error as AgentRoomsTestChatPersistenceError {
            throw error
        } catch AgentRoomsConversationPersistenceError.authorityMismatch,
                AgentRoomsConversationPersistenceError.ineligibleRoom {
            throw AgentRoomsTestChatPersistenceError.authorityMismatch
        } catch {
            throw AgentRoomsTestChatPersistenceError.corruptHistory
        }
    }

    private var conversationPersistence: AgentRoomsConversationPersistence {
        AgentRoomsConversationPersistence(database: database, repository: repository)
    }
}
