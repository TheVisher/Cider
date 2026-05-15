import Foundation

/// Lightweight display outline for long Kanban notes.
///
/// Raw `KanbanCard.notes` remains the source of truth. This parser only finds
/// common Markdown headings so the detail view and CLI handoffs can render long
/// cards as scannable sections without generating or rewriting user content.
struct KanbanCardNotesOutline: Equatable, Sendable {
    struct Section: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var body: String

        var bulletItems: [String] {
            body
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .compactMap { line in
                    let bullet = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
                    return bullet == line ? nil : bullet
                }
        }
    }

    var leadingText: String
    var sections: [Section]

    init(notes: String) {
        let lines = notes.components(separatedBy: .newlines)
        var leading: [String] = []
        var parsedSections: [Section] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flushSection() {
            guard let title = currentTitle else { return }
            parsedSections.append(
                Section(
                    id: "section-\(parsedSections.count)",
                    title: title,
                    body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            currentTitle = nil
            currentBody = []
        }

        for line in lines {
            if let heading = KanbanCardNotesOutline.markdownHeadingTitle(from: line) {
                flushSection()
                currentTitle = heading
            } else if currentTitle != nil {
                currentBody.append(line)
            } else {
                leading.append(line)
            }
        }

        flushSection()

        leadingText = leading.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        sections = parsedSections.filter { !$0.title.isEmpty || !$0.body.isEmpty }
    }

    var hasStructuredSections: Bool {
        !sections.isEmpty
    }

    private static func markdownHeadingTitle(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let afterHashes = trimmed.dropFirst(hashes)
        guard afterHashes.first == " " else { return nil }
        let title = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
