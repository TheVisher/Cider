import Foundation

enum CiderSurfacingExplanationService {
    static func recentCaptureExplanation(for item: LibraryItemV2) -> CiderSurfacingExplanation {
        let suggestedAction = recentCaptureSuggestedAction(for: item)
        return CiderSurfacingExplanation(
            reason: recentCaptureReason(for: item),
            urgency: surfacingUrgency(for: suggestedAction),
            sourceSignal: "recent_capture",
            reviewState: surfacingReviewState(for: suggestedAction),
            suggestedAction: suggestedAction,
            actionURLString: actionURLString(for: item)
        )
    }

    static func itemContextExplanation(for item: CiderItemSummary) -> CiderSurfacingExplanation? {
        guard item.folderID == nil || isInboxPath(item.relativePath) else { return nil }
        switch item.type {
        case .bookmark:
            return reviewExplanation(
                reason: "Still in Inbox / unfiled",
                suggestedAction: "Route to folder",
                sourceSignal: "item_context"
            )
        case .note:
            return reviewExplanation(
                reason: "Inbox note needs routing",
                suggestedAction: "Route to folder",
                sourceSignal: "item_context"
            )
        case .vaultFile:
            return reviewExplanation(
                reason: "Unfiled vault file",
                suggestedAction: "Route to folder",
                sourceSignal: "item_context"
            )
        default:
            return nil
        }
    }

    private static func reviewExplanation(
        reason: String,
        suggestedAction: String,
        sourceSignal: String
    ) -> CiderSurfacingExplanation {
        CiderSurfacingExplanation(
            reason: reason,
            urgency: "review",
            sourceSignal: sourceSignal,
            reviewState: "needs_review",
            suggestedAction: suggestedAction,
            actionURLString: nil
        )
    }

    private static func recentCaptureSuggestedAction(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark(let bookmark):
            if bookmarkGenericTitleReason(bookmark) != nil { return "Clean up title" }
            if bookmarkNeedsEnrichment(bookmark) { return "Needs enrichment" }
            if bookmark.folderID == nil { return "Route to folder" }
            return "Open"
        case .note(let note):
            if isUntitled(note.title) { return "Ask Erik" }
            if note.folderID == nil || isInboxPath(note.relativePath) { return "Route to folder" }
            return "Open"
        case .vaultFile(let file):
            if file.folderID == nil || isInboxPath(file.relativePath) { return "Route to folder" }
            return "Open"
        case .todo(let todo):
            if todo.isCompleted { return "Review" }
            return todo.earliestApproachingDate == nil ? "Add reminder" : "Do next"
        case .dateCard(let dateCard):
            return dateCard.actionURL == nil ? "Add action URL" : "Review"
        case .contact:
            return "Open"
        }
    }

    private static func recentCaptureReason(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark(let bookmark):
            if let reason = bookmarkGenericTitleReason(bookmark) { return reason }
            if bookmarkNeedsEnrichment(bookmark) { return "Bookmark needs enrichment" }
            if bookmark.folderID == nil { return "Still in Inbox / unfiled" }
            return "Recently captured bookmark"
        case .note(let note):
            if isUntitled(note.title) { return "Untitled inbox note" }
            if note.folderID == nil || isInboxPath(note.relativePath) { return "Inbox note needs routing" }
            return "Recently captured note"
        case .vaultFile(let file):
            if file.folderID == nil || isInboxPath(file.relativePath) { return "Unfiled vault file" }
            return "Recently captured file"
        case .todo(let todo):
            if todo.isCompleted { return "Completed todo surfaced recently" }
            return todo.earliestApproachingDate == nil ? "Todo is missing a reminder" : "Todo has a reminder"
        case .dateCard(let dateCard):
            return dateCard.actionURL == nil ? "Date is missing an action URL" : "Recent date item"
        case .contact:
            return "Recently updated contact"
        }
    }

    private static func surfacingUrgency(for suggestedAction: String) -> String {
        switch suggestedAction {
        case "Clean up title", "Needs enrichment", "Route to folder", "Ask Erik":
            return "review"
        case "Add reminder", "Add action URL", "Do next":
            return "action"
        default:
            return "normal"
        }
    }

    private static func surfacingReviewState(for suggestedAction: String) -> String {
        switch suggestedAction {
        case "Clean up title", "Needs enrichment", "Route to folder", "Ask Erik":
            return "needs_review"
        case "Add reminder", "Add action URL":
            return "pending"
        default:
            return "ok"
        }
    }

    private static func actionURLString(for item: LibraryItemV2) -> String? {
        switch item {
        case .bookmark(let bookmark):
            return bookmark.urlString
        case .todo(let todo):
            return todo.actionURLString
        case .dateCard(let dateCard):
            return dateCard.actionURLString
        default:
            return nil
        }
    }

    private static func bookmarkNeedsEnrichment(_ bookmark: Bookmark) -> Bool {
        let status = bookmark.enrichmentStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == nil || status == "none" || status == "partial" || status == "failed" || status == "error" { return true }
        return bookmarkGenericTitleReason(bookmark) != nil
    }

    private static func bookmarkGenericTitleReason(_ bookmark: Bookmark) -> String? {
        let title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = bookmark.hostDisplay.lowercased()
        guard !title.isEmpty else { return "Missing bookmark title" }
        if title == host || title == host.replacingOccurrences(of: "www.", with: "") {
            return "Generic host-only bookmark title"
        }
        if title == bookmark.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return "URL-only bookmark title"
        }
        return nil
    }

    private static func isUntitled(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed.hasPrefix("untitled")
    }

    private static func isInboxPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return path.lowercased().hasPrefix("inbox/")
    }
}
