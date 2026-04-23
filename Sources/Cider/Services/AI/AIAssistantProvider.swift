import Foundation

/// A message in an AI assistant conversation.
struct AIAssistantMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Context from the current Cider UI state, injected into AI prompts.
struct AIAssistantContext {
    var currentBookmark: (title: String, url: String, summary: String?)?
    var currentNote: (title: String, excerpt: String)?
    var currentFolder: (name: String, directItemCount: Int, childFolderCount: Int)?
    var currentEvent: (title: String, date: String, location: String)?
    var currentContact: (name: String, email: String)?
    var currentTodo: (title: String, status: String)?
    var selectedItemCount: Int = 0

    var isEmpty: Bool {
        currentBookmark == nil && currentNote == nil && currentFolder == nil &&
        currentEvent == nil && currentContact == nil && currentTodo == nil
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
            let summary = FolderCardSummary.build(
                directItemCount: folder.directItemCount,
                childFolderCount: folder.childFolderCount
            )
            parts.append("The user is browsing folder \"\(folder.name)\" containing \(summary.contentDescription).")
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
        if selectedItemCount > 1 {
            parts.append("The user has \(selectedItemCount) items selected.")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n")
    }
}

/// Protocol for AI backends (Foundation Models, MLX, etc.)
@MainActor
protocol AIAssistantProvider {
    /// Whether this provider is currently available.
    var isAvailable: Bool { get }

    /// Display name for the provider (e.g. "Apple Intelligence", "Qwen 3.5")
    var displayName: String { get }

    /// Stream a response to the given prompt with optional context.
    /// Yields text chunks as they're generated.
    func streamResponse(
        messages: [AIAssistantMessage],
        context: AIAssistantContext
    ) -> AsyncThrowingStream<String, Error>

    /// Reset conversation state (called when user clears the chat).
    func resetSession()
}
