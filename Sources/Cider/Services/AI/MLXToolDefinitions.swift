import Foundation

/// JSON schema definitions for all Cider tools, used in the MLX system prompt
/// so Qwen 2.5 can request tool calls via `<tool_call>` blocks.
enum MLXToolDefinitions {

    /// Returns a JSON array string describing every available tool.
    static func allToolsJSON() -> String {
        let tools: [[String: Any]] = [
            tool(
                name: "countItems",
                description: "Count the user's items in Cider. Can count bookmarks, notes, events, todos, contacts, folders, tags, clipboard items, or browser sessions. Use itemType \"all\" for a summary of everything.",
                properties: [
                    "itemType": prop("string", "Type of item to count: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, sessions, or all")
                ],
                required: ["itemType"]
            ),
            tool(
                name: "searchItems",
                description: "Search the user's bookmarks, notes, events, todos, and contacts by keyword. Returns matching items with titles and details.",
                properties: [
                    "query": prop("string", "Search query — keywords to search for across titles, URLs, content, and tags"),
                    "itemType": prop("string", "Optional: limit to a specific type (bookmarks, notes, events, todos, contacts). Leave empty to search all.")
                ],
                required: ["query"]
            ),
            tool(
                name: "listFolders",
                description: "List all folders in the user's vault with the number of items in each.",
                properties: [:],
                required: []
            ),
            tool(
                name: "listTags",
                description: "List all tags/labels the user has created, with how many items use each tag.",
                properties: [:],
                required: []
            ),
            tool(
                name: "getRecentItems",
                description: "Get items the user recently created or modified. Shows the most recent bookmarks, notes, events, todos, and contacts.",
                properties: [
                    "days": prop("integer", "Number of days to look back (e.g. 1 for today, 7 for this week)")
                ],
                required: ["days"]
            ),
            tool(
                name: "getItemsByTag",
                description: "Find all items (bookmarks, notes, events, todos, contacts) that have a specific tag/label.",
                properties: [
                    "tagName": prop("string", "The tag/label name to search for")
                ],
                required: ["tagName"]
            ),
            tool(
                name: "getUpcomingEvents",
                description: "Get upcoming events and date cards. Shows events happening soon.",
                properties: [
                    "days": prop("integer", "Number of days ahead to look (e.g. 7 for this week, 30 for this month)")
                ],
                required: ["days"]
            ),
            tool(
                name: "getOverdueTodos",
                description: "Get incomplete todos that are past their due date, plus any high-priority tasks.",
                properties: [:],
                required: []
            ),
            tool(
                name: "getFolderContents",
                description: "Get the contents of a specific folder — lists all bookmarks, notes, events, todos, and contacts inside it.",
                properties: [
                    "folderName": prop("string", "The folder name to look inside")
                ],
                required: ["folderName"]
            ),
            tool(
                name: "getBrowserSessions",
                description: "Get the user's saved browser sessions — groups of tabs saved from their browser.",
                properties: [:],
                required: []
            ),
            tool(
                name: "createFolder",
                description: "Create a new folder in the user's vault. Can create root-level folders or sub-folders inside an existing folder.",
                properties: [
                    "folderName": prop("string", "Name of the folder to create"),
                    "parentFolderName": prop("string", "Optional: name of the parent folder to create this inside. Leave empty for root level.")
                ],
                required: ["folderName"]
            ),
            tool(
                name: "moveToFolder",
                description: "Move bookmarks or notes into a folder. Search for items by title keyword, then move matching items to the specified folder.",
                properties: [
                    "searchQuery": prop("string", "Keyword to find items to move (searches bookmark and note titles)"),
                    "folderName": prop("string", "Name of the destination folder")
                ],
                required: ["searchQuery", "folderName"]
            ),
            tool(
                name: "applyTag",
                description: "Apply a tag/label to items. Searches for items by keyword and applies the specified tag. Creates the tag if it doesn't exist.",
                properties: [
                    "searchQuery": prop("string", "Keyword to find items to tag (searches titles)"),
                    "tagName": prop("string", "Tag name to apply (will be created if it doesn't exist)")
                ],
                required: ["searchQuery", "tagName"]
            ),
            tool(
                name: "removeTag",
                description: "Remove a tag/label from items. Searches for items by keyword and removes the specified tag.",
                properties: [
                    "searchQuery": prop("string", "Keyword to find items to untag (searches titles)"),
                    "tagName": prop("string", "Tag name to remove")
                ],
                required: ["searchQuery", "tagName"]
            ),
            tool(
                name: "renameBookmark",
                description: "Rename a bookmark. Searches by current title and sets a new title.",
                properties: [
                    "currentTitle": prop("string", "Current title (or part of it) to find the bookmark"),
                    "newTitle": prop("string", "The new title to set")
                ],
                required: ["currentTitle", "newTitle"]
            ),
            tool(
                name: "findSimilar",
                description: "Find bookmarks that are similar to a specific bookmark, using AI embeddings. Searches by title keyword to identify the source bookmark.",
                properties: [
                    "bookmarkTitle": prop("string", "Title (or part of it) of the bookmark to find similar items for")
                ],
                required: ["bookmarkTitle"]
            ),
            tool(
                name: "createNote",
                description: "Create a new note in the user's vault. Can include title and content. Optionally place it in a specific folder.",
                properties: [
                    "title": prop("string", "Title for the note"),
                    "content": prop("string", "Content/body text for the note"),
                    "folderName": prop("string", "Optional: folder name to place the note in")
                ],
                required: ["title", "content"]
            ),
            tool(
                name: "summarizeText",
                description: "Summarize a piece of text using Apple Intelligence. Can optionally save the summary as a new note.",
                properties: [
                    "text": prop("string", "The text to summarize"),
                    "saveAsNote": prop("boolean", "Optional: if true, save the summary as a new note"),
                    "noteTitle": prop("string", "Optional: title for the note (if saving)"),
                    "folderName": prop("string", "Optional: folder name to save the note in")
                ],
                required: ["text"]
            ),
            tool(
                name: "addBookmark",
                description: "Save a new bookmark from a URL. Can optionally set a title, folder, and tags.",
                properties: [
                    "url": prop("string", "The URL to bookmark"),
                    "title": prop("string", "Optional: title for the bookmark"),
                    "folderName": prop("string", "Optional: folder name to save the bookmark in"),
                    "tagName": prop("string", "Optional: tag name to apply to the bookmark")
                ],
                required: ["url"]
            ),
            tool(
                name: "getCurrentItem",
                description: "Get full details about the item the user is currently viewing in Cider. Use this when the user says \"this bookmark\", \"this note\", \"summarize this\", etc.",
                properties: [:],
                required: []
            ),
            tool(
                name: "deleteItem",
                description: "Delete a bookmark or note by moving it to the trash. Searches by title keyword. Items can be recovered from trash later.",
                properties: [
                    "searchQuery": prop("string", "Title (or part of it) of the item to delete"),
                    "itemType": prop("string", "Type of item to delete: bookmark or note")
                ],
                required: ["searchQuery", "itemType"]
            ),
            tool(
                name: "renameFolder",
                description: "Rename an existing folder.",
                properties: [
                    "currentName": prop("string", "Current name of the folder to rename"),
                    "newName": prop("string", "New name for the folder")
                ],
                required: ["currentName", "newName"]
            ),
            tool(
                name: "unfileItems",
                description: "Remove items from their folder, making them unfiled (root level). Searches by keyword and removes folder assignment.",
                properties: [
                    "searchQuery": prop("string", "Keyword to find items to unfile (searches titles)")
                ],
                required: ["searchQuery"]
            ),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: tools, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Helpers

    private static func tool(
        name: String,
        description: String,
        properties: [String: [String: String]],
        required: [String]
    ) -> [String: Any] {
        var params: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            params["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "parameters": params
        ]
    }

    private static func prop(_ type: String, _ description: String) -> [String: String] {
        ["type": type, "description": description]
    }
}
