import Foundation

struct ChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    let modelID: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [AIChatMessage]

    init(id: UUID = UUID(), title: String = "New Chat", modelID: String, createdAt: Date = Date(), updatedAt: Date = Date(), messages: [AIChatMessage] = []) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// Preview snippet from first user message.
    var preview: String {
        messages.first(where: { $0.role == .user })?.content ?? ""
    }
}
