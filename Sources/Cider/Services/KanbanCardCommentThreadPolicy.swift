import Foundation

struct KanbanCardCommentThreadPolicy: Equatable, Sendable {
    struct Thread: Equatable, Sendable {
        var root: KanbanCardComment
        var replies: [KanbanCardComment]

        var isResolved: Bool { root.isResolved }
        var commentCount: Int { 1 + replies.count }
    }

    static func threads(from comments: [KanbanCardComment]) -> [Thread] {
        let sortedComments = comments.sorted { $0.createdAt < $1.createdAt }
        let roots = sortedComments.filter { ($0.parentCommentID ?? "").isEmpty }
        return roots.map { root in
            Thread(
                root: root,
                replies: sortedComments.filter { $0.parentCommentID == root.id }
            )
        }
    }

    static func displayThreads(from comments: [KanbanCardComment]) -> [Thread] {
        threads(from: comments)
    }

    static func defaultCollapsedThreadIDs(from comments: [KanbanCardComment]) -> Set<String> {
        Set(threads(from: comments).filter { $0.isResolved }.map(\.root.id))
    }

    static func threadCounts(from comments: [KanbanCardComment]) -> (active: Int, resolved: Int) {
        let threads = threads(from: comments)
        let resolvedCount = threads.filter { $0.isResolved }.count
        return (threads.count - resolvedCount, resolvedCount)
    }

    static func defaultAuthorName(
        accountEmail: String?,
        fullUserName: String?,
        userName: String?
    ) -> String {
        if let accountName = displayName(fromAccountEmail: accountEmail) {
            return accountName
        }
        if let fullUserName = cleanedName(fullUserName), !genericSystemNames.contains(fullUserName.lowercased()) {
            return fullUserName
        }
        if let userName = cleanedName(userName) {
            return titleCasedIdentifier(userName)
        }
        return "Cider User"
    }

    static func displayBodyLines(for body: String) -> [String] {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return normalized.components(separatedBy: .newlines)
    }

    private static let genericSystemNames: Set<String> = ["user", "unknown", "mac", "local"]

    private static func displayName(fromAccountEmail email: String?) -> String? {
        guard let email = cleanedName(email) else { return nil }
        let localPart = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? email
        return titleCasedIdentifier(localPart)
    }

    private static func cleanedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func titleCasedIdentifier(_ value: String) -> String {
        let words = value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        let displayName = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? value : displayName
    }
}
