import Foundation

struct KanbanCardCommentThreadPolicy: Equatable, Sendable {
    struct ChecklistItem: Equatable, Sendable, Identifiable {
        var commentID: String
        var lineIndex: Int
        var text: String
        var isChecked: Bool

        var id: String { anchorID }
        var anchorID: String { "\(commentID)#checklist-\(lineIndex + 1)" }
        var markdownQuote: String { "- [\(isChecked ? "x" : " ")] \(text)" }
    }

    struct ChecklistLine: Equatable, Sendable {
        var text: String
        var isChecked: Bool
        var marker: String
    }

    struct QuotedLine: Equatable, Sendable {
        var content: String
    }

    struct ReferenceLink: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            case link
            case image
        }

        var id: String { url.absoluteString }
        var url: URL
        var label: String?
        var kind: Kind

        var displayTitle: String {
            if let label = cleanedDisplay(label) {
                return label
            }
            return url.host(percentEncoded: false) ?? url.absoluteString
        }

        var displaySubtitle: String {
            url.absoluteString
        }
    }

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

    static func resolvedSummaryText(for comment: KanbanCardComment) -> String {
        let resolver = cleanedName(comment.resolvedBy) ?? "Someone"
        return "\(resolver) resolved the thread"
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

    static func quotedLine(_ line: String) -> QuotedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return QuotedLine(content: content)
    }

    static func checklistLineContent(_ line: String) -> ChecklistLine? {
        checklistLine(line)
    }

    static func checklistItems(in comment: KanbanCardComment) -> [ChecklistItem] {
        displayBodyLines(for: comment.body).enumerated().compactMap { index, line in
            checklistLineContent(line).map { item in
                ChecklistItem(
                    commentID: comment.id,
                    lineIndex: index,
                    text: item.text,
                    isChecked: item.isChecked
                )
            }
        }
    }

    static func toggledChecklistBody(_ body: String, lineIndex: Int) -> String? {
        var lines = displayBodyLines(for: body)
        guard lines.indices.contains(lineIndex),
              let checklist = checklistLine(lines[lineIndex])
        else { return nil }

        let original = lines[lineIndex]
        guard let markerRange = original.range(of: checklist.marker) else { return nil }
        let replacement = checklist.isChecked ? "[ ]" : "[x]"
        lines[lineIndex].replaceSubrange(markerRange, with: replacement)
        return lines.joined(separator: "\n")
    }

    static func canResolveTestingChecklist(_ comment: KanbanCardComment) -> Bool {
        guard comment.kind == .qa else { return false }
        let items = checklistItems(in: comment)
        return !items.isEmpty && items.allSatisfy(\.isChecked)
    }

    static func failureReply(
        to comment: KanbanCardComment,
        checklistItem: ChecklistItem,
        author: String?,
        createdAt: Date = Date()
    ) -> KanbanCardComment {
        KanbanCardComment(
            kind: .qa,
            body: """
            > \(checklistItem.markdownQuote)

            Failed because:

            """,
            author: author,
            source: "cider-ui",
            createdAt: createdAt,
            parentCommentID: comment.id,
            parentChecklistItemAnchor: checklistItem.anchorID,
            quotedChecklistItem: checklistItem.text
        )
    }

    static func referenceLinks(in body: String) -> [ReferenceLink] {
        var links: [ReferenceLink] = []
        var seen = Set<String>()

        for match in markdownLinkMatches(in: body) {
            appendReference(
                urlString: match.urlString,
                label: match.label,
                kind: match.isImage ? .image : .link,
                links: &links,
                seen: &seen
            )
        }

        for urlString in bareURLStrings(in: body) {
            appendReference(urlString: urlString, label: nil, kind: .link, links: &links, seen: &seen)
        }

        return links
    }

    private static let genericSystemNames: Set<String> = ["user", "unknown", "mac", "local"]

    private static func checklistLine(_ line: String) -> ChecklistLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marker: String
        let isChecked: Bool
        if trimmed.hasPrefix("- [ ] ") {
            marker = "[ ]"
            isChecked = false
        } else if trimmed.hasPrefix("- [x] ") {
            marker = "[x]"
            isChecked = true
        } else if trimmed.hasPrefix("- [X] ") {
            marker = "[X]"
            isChecked = true
        } else {
            return nil
        }
        return ChecklistLine(text: String(trimmed.dropFirst(6)), isChecked: isChecked, marker: marker)
    }

    private static func appendReference(
        urlString: String,
        label: String?,
        kind: ReferenceLink.Kind,
        links: inout [ReferenceLink],
        seen: inout Set<String>
    ) {
        let cleanedURLString = cleanURLString(urlString)
        guard let url = URL(string: cleanedURLString), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        guard seen.insert(url.absoluteString).inserted else { return }
        links.append(ReferenceLink(url: url, label: label, kind: kind))
    }

    private static func markdownLinkMatches(in body: String) -> [(label: String?, urlString: String, isImage: Bool)] {
        let pattern = "(!)?\\[([^\\]]*)\\]\\((https?://[^\\s)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.matches(in: body, range: range).compactMap { match in
            guard
                let urlRange = Range(match.range(at: 3), in: body)
            else { return nil }
            let labelRange = Range(match.range(at: 2), in: body)
            return (
                label: labelRange.map { String(body[$0]) },
                urlString: String(body[urlRange]),
                isImage: match.range(at: 1).location != NSNotFound
            )
        }
    }

    private static func bareURLStrings(in body: String) -> [String] {
        let pattern = "https?://[^\\s<>)\\]]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.matches(in: body, range: range).compactMap { match in
            Range(match.range, in: body).map { String(body[$0]) }
        }
    }

    private static func cleanURLString(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}").union(.whitespacesAndNewlines))
    }

    private static func cleanedDisplay(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

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
