import Foundation

/// Registers all Cider tools into the unified AgentToolRegistry.
/// Called once on app launch. Each tool's execute closure delegates to
/// MLXToolExecutor which already has the string-based interface we need.
enum AgentToolRegistration {

    @MainActor
    static func registerAll() async {
        let registry = AgentToolRegistry.shared

        // MARK: - Read Tools

        await registry.register(AgentToolDefinition(
            name: "countItems",
            description: "Count the user's items in Cider. Can count bookmarks, notes, events, todos, contacts, folders, tags, or clipboard items.",
            parameters: [
                AgentToolParameter(name: "itemType", type: .string, description: "Type of item to count: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, or all", required: true)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "countItems", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "searchItems",
            description: "Search bookmarks, notes, events, todos, and contacts by keyword.",
            parameters: [
                AgentToolParameter(name: "query", type: .string, description: "Search query — keywords to search across titles, URLs, content, and tags", required: true),
                AgentToolParameter(name: "itemType", type: .string, description: "Optional: limit to bookmarks, notes, events, todos, or contacts", required: false)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "searchItems", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "listFolders",
            description: "List all folders in the user's vault with item counts.",
            parameters: [],
            categories: [.vaultRead],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "listFolders", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "listTags",
            description: "List all tags with the number of items using each tag.",
            parameters: [],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "listTags", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getRecentItems",
            description: "Get the most recently saved or updated items.",
            parameters: [
                AgentToolParameter(name: "count", type: .integer, description: "Number of items to return (default 10)", required: false),
                AgentToolParameter(name: "itemType", type: .string, description: "Optional: limit to bookmarks, notes, events, todos, or contacts", required: false)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getRecentItems", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getItemsByTag",
            description: "Get all items with a specific tag.",
            parameters: [
                AgentToolParameter(name: "tagName", type: .string, description: "Tag name to search for", required: true)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getItemsByTag", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getUpcomingEvents",
            description: "Get upcoming events and date cards within a time window.",
            parameters: [
                AgentToolParameter(name: "days", type: .integer, description: "Number of days ahead to look (default 7)", required: false)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getUpcomingEvents", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getOverdueTodos",
            description: "Get todos that are past their due date.",
            parameters: [
                AgentToolParameter(name: "days", type: .integer, description: "Include todos overdue within this many days (default 7)", required: false)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getOverdueTodos", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getFolderContents",
            description: "Get the contents of a specific folder.",
            parameters: [
                AgentToolParameter(name: "folderName", type: .string, description: "Name of the folder to list contents of", required: true)
            ],
            categories: [.vaultRead],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getFolderContents", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "findSimilar",
            description: "Find items similar to a given item using embeddings.",
            parameters: [
                AgentToolParameter(name: "query", type: .string, description: "Text or title to find similar items for", required: true),
                AgentToolParameter(name: "count", type: .integer, description: "Number of results (default 5)", required: false)
            ],
            categories: [.search],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "findSimilar", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "getCurrentItem",
            description: "Get details about the item the user is currently viewing.",
            parameters: [],
            categories: [.vaultRead],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "getCurrentItem", arguments: args) }
        ))

        // MARK: - Write Tools

        await registry.register(AgentToolDefinition(
            name: "createFolder",
            description: "Create a new folder in the vault.",
            parameters: [
                AgentToolParameter(name: "folderName", type: .string, description: "Name of the folder to create", required: true),
                AgentToolParameter(name: "parentFolderName", type: .string, description: "Optional parent folder name", required: false)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "createFolder", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "moveToFolder",
            description: "Move items to a folder by searching for them by title.",
            parameters: [
                AgentToolParameter(name: "searchQuery", type: .string, description: "Keyword to find items to move", required: true),
                AgentToolParameter(name: "folderName", type: .string, description: "Destination folder name", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "moveToFolder", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "applyTag",
            description: "Add a tag to items matching a search query.",
            parameters: [
                AgentToolParameter(name: "searchQuery", type: .string, description: "Keyword to find items to tag", required: true),
                AgentToolParameter(name: "tagName", type: .string, description: "Tag to apply", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "applyTag", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "removeTag",
            description: "Remove a tag from items matching a search query.",
            parameters: [
                AgentToolParameter(name: "searchQuery", type: .string, description: "Keyword to find items to untag", required: true),
                AgentToolParameter(name: "tagName", type: .string, description: "Tag to remove", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "removeTag", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "renameBookmark",
            description: "Rename a bookmark by searching for it.",
            parameters: [
                AgentToolParameter(name: "currentTitle", type: .string, description: "Keyword to find the bookmark", required: true),
                AgentToolParameter(name: "newTitle", type: .string, description: "New title for the bookmark", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "renameBookmark", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "createNote",
            description: "Create a new note in the vault.",
            parameters: [
                AgentToolParameter(name: "title", type: .string, description: "Title of the note", required: true),
                AgentToolParameter(name: "content", type: .string, description: "Markdown content of the note", required: false),
                AgentToolParameter(name: "folderName", type: .string, description: "Optional folder to create the note in", required: false)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "createNote", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "addBookmark",
            description: "Save a new bookmark to the vault.",
            parameters: [
                AgentToolParameter(name: "url", type: .string, description: "URL to bookmark", required: true),
                AgentToolParameter(name: "title", type: .string, description: "Optional title (auto-fetched if omitted)", required: false),
                AgentToolParameter(name: "folderName", type: .string, description: "Optional folder name", required: false),
                AgentToolParameter(name: "tags", type: .string, description: "Optional comma-separated tags", required: false)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "addBookmark", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "renameFolder",
            description: "Rename an existing folder.",
            parameters: [
                AgentToolParameter(name: "currentName", type: .string, description: "Current folder name", required: true),
                AgentToolParameter(name: "newName", type: .string, description: "New folder name", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "renameFolder", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "unfileItems",
            description: "Remove items from their folder (move to root).",
            parameters: [
                AgentToolParameter(name: "searchQuery", type: .string, description: "Keyword to find items to unfile", required: true)
            ],
            categories: [.vaultWrite],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "unfileItems", arguments: args) }
        ))

        // MARK: - Delete Tools

        await registry.register(AgentToolDefinition(
            name: "deleteItem",
            description: "Delete an item by searching for it (moves to trash).",
            parameters: [
                AgentToolParameter(name: "searchQuery", type: .string, description: "Keyword to find the item to delete", required: true),
                AgentToolParameter(name: "itemType", type: .string, description: "Type of item: bookmark, note, event, todo, contact", required: false)
            ],
            categories: [.vaultDelete],
            requiresConfirmation: true,  // Destructive — needs confirmation on remote channels
            execute: { args in MLXToolExecutor.execute(name: "deleteItem", arguments: args) }
        ))

        // MARK: - Reminder Tools

        await registry.register(AgentToolDefinition(
            name: "createReminder",
            description: "Create a reminder or recurring event with notification rules.",
            parameters: [
                AgentToolParameter(name: "title", type: .string, description: "Title of the reminder", required: true),
                AgentToolParameter(name: "date", type: .string, description: "Date in yyyy-MM-dd format", required: true),
                AgentToolParameter(name: "frequency", type: .string, description: "Recurrence: daily, weekly, monthly, yearly, or empty for one-time", required: false),
                AgentToolParameter(name: "remindMinutesBefore", type: .integer, description: "Minutes before event to remind (1440=1day, 60=1hr, 0=at-time)", required: false),
                AgentToolParameter(name: "secondRemindMinutesBefore", type: .integer, description: "Optional second reminder offset", required: false),
                AgentToolParameter(name: "location", type: .string, description: "Optional location", required: false),
                AgentToolParameter(name: "details", type: .string, description: "Optional details", required: false)
            ],
            categories: [.reminder],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "createReminder", arguments: args) }
        ))

        await registry.register(AgentToolDefinition(
            name: "cancelReminder",
            description: "Cancel a reminder by title — either delete entirely or just disable notifications.",
            parameters: [
                AgentToolParameter(name: "title", type: .string, description: "Title or partial title of the reminder to cancel", required: true),
                AgentToolParameter(name: "deleteEntirely", type: .boolean, description: "If true, delete the event. If false, just disable notifications.", required: false)
            ],
            categories: [.reminder],
            requiresConfirmation: true,
            execute: { args in MLXToolExecutor.execute(name: "cancelReminder", arguments: args) }
        ))

        // MARK: - System Tools

        await registry.register(AgentToolDefinition(
            name: "summarizeText",
            description: "Summarize a block of text using AI.",
            parameters: [
                AgentToolParameter(name: "text", type: .string, description: "Text to summarize", required: true)
            ],
            categories: [.system],
            requiresConfirmation: false,
            execute: { args in MLXToolExecutor.execute(name: "summarizeText", arguments: args) }
        ))
    }
}
