import Foundation

// MARK: - Agent Message

/// A message in an agent conversation thread.
struct AgentMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: AgentMessageRole
    var content: String
    let timestamp: Date

    enum AgentMessageRole: String, Codable, Sendable {
        case user
        case assistant
        case toolResult
    }

    init(id: UUID = UUID(), role: AgentMessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    static func user(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, content: text)
    }

    static func assistant(_ text: String) -> AgentMessage {
        AgentMessage(role: .assistant, content: text)
    }

    static func toolResult(name: String, result: String) -> AgentMessage {
        AgentMessage(role: .toolResult, content: "[\(name)] \(result)")
    }
}

// MARK: - Agent Channel

enum AgentChannel: String, Codable, Sendable {
    case uiPanel
    case iMessage
    case telegram
    case shareIngress
    case iosApp
    case system
    case notification
}

// MARK: - Agent Context

/// Context from the current Cider UI state or wake event, injected into AI prompts.
struct AgentContext: Sendable {
    var currentBookmark: BookmarkContext?
    var currentNote: NoteContext?
    var currentFolder: FolderContext?
    var currentEvent: EventContext?
    var currentContact: ContactContext?
    var currentTodo: TodoContext?
    var selectedItemCount: Int = 0
    var reminderContext: ReminderContext?

    struct BookmarkContext: Sendable { let title: String; let url: String; let summary: String? }
    struct NoteContext: Sendable { let title: String; let excerpt: String }
    struct FolderContext: Sendable { let name: String; let itemCount: Int }
    struct EventContext: Sendable { let title: String; let date: String; let location: String }
    struct ContactContext: Sendable { let name: String; let email: String }
    struct TodoContext: Sendable { let title: String; let status: String }
    struct ReminderContext: Sendable, Codable {
        let cardID: UUID
        let title: String
        let occurrence: Date
        let minutesBefore: Int
        let isRecurring: Bool
        let details: String
        let location: String
    }

    static let empty = AgentContext()

    var isEmpty: Bool {
        currentBookmark == nil && currentNote == nil && currentFolder == nil &&
        currentEvent == nil && currentContact == nil && currentTodo == nil &&
        reminderContext == nil
    }

    /// Builds a context string for injection into the system prompt.
    var contextDescription: String {
        var parts: [String] = []

        if let bookmark = currentBookmark {
            var desc = "The user is viewing a bookmark: \"\(bookmark.title)\" (\(bookmark.url))"
            if let summary = bookmark.summary { desc += " — Summary: \(summary)" }
            parts.append(desc)
        }
        if let note = currentNote {
            parts.append("The user is viewing a note: \"\(note.title)\" — Content: \(note.excerpt)")
        }
        if let folder = currentFolder {
            parts.append("The user is browsing folder \"\(folder.name)\" containing \(folder.itemCount) items.")
        }
        if let event = currentEvent {
            var desc = "The user is viewing an event: \"\(event.title)\" on \(event.date)"
            if !event.location.isEmpty { desc += " at \(event.location)" }
            parts.append(desc)
        }
        if let contact = currentContact {
            var desc = "The user is viewing a contact: \"\(contact.name)\""
            if !contact.email.isEmpty { desc += " (\(contact.email))" }
            parts.append(desc)
        }
        if let todo = currentTodo {
            parts.append("The user is viewing a todo: \"\(todo.title)\" (\(todo.status))")
        }
        if let reminder = reminderContext {
            parts.append("Delivering reminder: \"\(reminder.title)\" — due \(reminder.occurrence)")
        }
        if selectedItemCount > 1 {
            parts.append("The user has \(selectedItemCount) items selected.")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n")
    }
}

// MARK: - Agent Envelope

/// Every inbound message is wrapped in an envelope that carries sender identity,
/// channel metadata, and routing info.
struct AgentEnvelope: Sendable {
    let text: String
    let threadID: UUID
    let channel: AgentChannel
    let channelThreadID: String?
    let context: AgentContext
    let senderID: String?
    let senderDisplayName: String?
    let metadata: [String: String]

    static func uiPanel(text: String, threadID: UUID, context: AgentContext) -> AgentEnvelope {
        AgentEnvelope(
            text: text,
            threadID: threadID,
            channel: .uiPanel,
            channelThreadID: threadID.uuidString,
            context: context,
            senderID: nil,
            senderDisplayName: nil,
            metadata: [:]
        )
    }

    static func system(text: String, threadID: UUID, context: AgentContext) -> AgentEnvelope {
        AgentEnvelope(
            text: text,
            threadID: threadID,
            channel: .system,
            channelThreadID: threadID.uuidString,
            context: context,
            senderID: nil,
            senderDisplayName: nil,
            metadata: [:]
        )
    }

    static func telegram(
        text: String,
        threadID: UUID,
        channelThreadID: String,
        context: AgentContext,
        senderID: String?,
        senderDisplayName: String?
    ) -> AgentEnvelope {
        AgentEnvelope(
            text: text,
            threadID: threadID,
            channel: .telegram,
            channelThreadID: channelThreadID,
            context: context,
            senderID: senderID,
            senderDisplayName: senderDisplayName,
            metadata: [:]
        )
    }
}

// MARK: - Agent Response

struct AgentResponse: Sendable {
    let text: String
    let toolCallsMade: [AgentToolCall]
}

struct AgentToolCall: Sendable {
    let name: String
    let arguments: [String: String]  // Simplified for Sendable — real impl may need more
    let result: String
}

// MARK: - Agent Error

enum AgentError: Error, LocalizedError {
    case unauthorized
    case providerUnavailable
    case toolDenied(String)
    case maxRoundsExceeded
    case deliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized sender"
        case .providerUnavailable: return "AI provider is not available"
        case .toolDenied(let name): return "Tool '\(name)' is not permitted on this channel"
        case .maxRoundsExceeded: return "Maximum tool call rounds exceeded"
        case .deliveryFailed(let reason): return "Message delivery failed: \(reason)"
        }
    }
}
