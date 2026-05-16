import Foundation

/// A message in an AI assistant conversation.
struct AIAssistantMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var sourceID: String?
    var sourceSessionID: String?
    var sourceName: String?
    var attachments: [AIAssistantAttachment]

    enum Role: String, Codable, Equatable {
        case user
        case assistant
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case timestamp
        case sourceID
        case sourceSessionID
        case sourceName
        case attachments
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        sourceID: String? = nil,
        sourceSessionID: String? = nil,
        sourceName: String? = nil,
        attachments: [AIAssistantAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sourceID = sourceID
        self.sourceSessionID = sourceSessionID
        self.sourceName = sourceName
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
        sourceSessionID = try container.decodeIfPresent(String.self, forKey: .sourceSessionID)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        attachments = try container.decodeIfPresent([AIAssistantAttachment].self, forKey: .attachments) ?? []
    }
}

struct AIAssistantAttachment: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case image
    }

    let id: String
    let kind: Kind
    var mimeType: String?
    var localFilePath: String?
    var remoteURL: String?
    var altText: String?

    init(
        id: String,
        kind: Kind,
        mimeType: String? = nil,
        localFilePath: String? = nil,
        remoteURL: String? = nil,
        altText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.localFilePath = localFilePath
        self.remoteURL = remoteURL
        self.altText = altText
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
    var currentItemRef: LibraryEntityRef?
    var currentItemContext: CiderItemAgentContextPacket?
    var selectedItemCount: Int = 0

    var isEmpty: Bool {
        currentBookmark == nil && currentNote == nil && currentFolder == nil &&
        currentEvent == nil && currentContact == nil && currentTodo == nil &&
        currentItemContext == nil
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
        if let currentItemContext {
            parts.append(currentItemContext.assistantContextDescription)
        }
        if selectedItemCount > 1 {
            parts.append("The user has \(selectedItemCount) items selected.")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n")
    }
}

extension CiderItemAgentContextPacket {
    var assistantContextDescription: String {
        var parts: [String] = [
            "Unified current item context: \(item.type.rawValue) \"\(item.title)\" (\(item.id.uuidString))",
            "Summary: \(summary)",
        ]

        if !provenance.isEmpty {
            parts.append("Provenance: \(provenance.joined(separator: "; "))")
        }
        if let review {
            var reviewLine = "Review: \(review.status) - \(review.reason)"
            if let targetPath = review.targetPath {
                reviewLine += " -> \(targetPath)"
            }
            parts.append(reviewLine)
        }
        if !contentBlocks.isEmpty {
            let blockSummaries = contentBlocks
                .prefix(2)
                .map { "\($0.title): \($0.body)" }
                .joined(separator: " | ")
            parts.append("Context blocks: \(blockSummaries)")
        }
        if !related.isEmpty {
            parts.append("Related items: \(related.prefix(3).map(\.title).joined(separator: "; "))")
        }
        if !recentHistory.isEmpty {
            parts.append("Recent history: \(recentHistory.prefix(3).map(\.summary).joined(separator: "; "))")
        }
        if !safeCommands.isEmpty {
            parts.append("Safe commands: \(safeCommands.joined(separator: "; "))")
        }

        return parts.joined(separator: "\n")
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
