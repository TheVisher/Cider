import AppKit
import Foundation

enum NoteContentIOOperation: String, Equatable, Sendable {
    case read
    case write
}

struct NoteContentIOIssue: Equatable, Sendable {
    let noteID: UUID
    let relativePath: String
    let fileURL: URL
    let operation: NoteContentIOOperation
    let message: String

    init(noteID: UUID, relativePath: String, fileURL: URL, operation: NoteContentIOOperation, error: Error) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.operation = operation
        self.message = error.localizedDescription
    }
}

struct NoteContentResult: Equatable, Sendable {
    let content: String?
    let issue: NoteContentIOIssue?

    static func success(_ content: String) -> NoteContentResult {
        NoteContentResult(content: content, issue: nil)
    }

    static func failure(_ issue: NoteContentIOIssue) -> NoteContentResult {
        NoteContentResult(content: nil, issue: issue)
    }
}

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var summary: String?
    var createdAt: Date
    var modifiedAt: Date
    /// Relative path within the notes directory (e.g. "My Note.md")
    var relativePath: String
    var labelIDs: [UUID]
    var folderID: UUID?
    var isPinned: Bool
    var tags: [String]
    /// Explicit project owner for file-backed project artifacts. Path containment is storage topology only.
    var projectID: String?
    /// Project artifact kind such as "note", "decision", "qa", "handoff", or "plan".
    var artifactType: String?

    init(id: UUID = UUID(), title: String, content: String = "", summary: String? = nil, createdAt: Date = Date(), modifiedAt: Date = Date(), relativePath: String = "", labelIDs: [UUID] = [], folderID: UUID? = nil, isPinned: Bool = false, tags: [String] = [], projectID: String? = nil, artifactType: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.summary = summary
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.relativePath = relativePath
        self.labelIDs = labelIDs
        self.folderID = folderID
        self.isPinned = isPinned
        self.tags = tags
        self.projectID = projectID
        self.artifactType = artifactType
    }

    var isProjectArtifact: Bool {
        projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var projectPlanMetadata: ProjectPlanMetadata? {
        ProjectPlanMetadata(note: self)
    }

    var isDailyJournalNote: Bool {
        title.range(
            of: #"^Daily Journal \d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil
    }

    var dailyJournalDateLabel: String? {
        guard isDailyJournalNote else { return nil }
        return String(title.dropFirst("Daily Journal ".count))
    }

    var journalCaptureSubtitle: String? {
        guard isDailyJournalNote else { return nil }
        if let dailyJournalDateLabel {
            return "Journal capture - \(dailyJournalDateLabel)"
        }
        return "Journal capture"
    }

    // MARK: - Computed Properties for Card Display

    /// The raw content to use for display — loads from disk if the in-memory field is empty.
    /// Internal so NoteCardData.load() can call it once and pass through.
    var resolvedContent: String {
        if let content = resolvedContentResult.content {
            return content
        }
        return ""
    }

    var resolvedContentResult: NoteContentResult {
        if !content.isEmpty { return .success(content) }
        guard !relativePath.isEmpty else { return .success("") }
        let fileURL = absoluteFileURL
        do {
            return .success(try String(contentsOf: fileURL, encoding: .utf8))
        } catch {
            return .failure(NoteContentIOIssue(
                noteID: id,
                relativePath: relativePath,
                fileURL: fileURL,
                operation: .read,
                error: error
            ))
        }
    }

    /// Resolves the absolute file URL for this note.
    /// Notes in vault folders have a relativePath containing "/" (e.g. "Work/My Note.md").
    /// Notes in the default Notes/ dir have a plain filename (e.g. "My Note.md").
    var absoluteFileURL: URL {
        if relativePath.contains("/") {
            // Vault-relative path (note lives in a vault folder)
            return StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath)
        }
        // Default: file is in the Notes/ directory
        return StoragePaths.cachedDirectoryURL(for: .notes).appendingPathComponent(relativePath)
    }

    // Pre-compiled regexes for image extraction
    private static let mdImageRegex = makeImageRegex(pattern: #"!\[[^\]]*\]\(([^\)]+)\)"#)
    private static let htmlImageRegex = makeImageRegex(
        pattern: #"<img\s[^>]*src=[\"']([^\"']+)[\"']"#,
        options: .caseInsensitive
    )

    private static func makeImageRegex(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
            return regex
        }
        preconditionFailure("Invalid built-in note image regex pattern: \(pattern)")
    }

    /// Extract image URLs from markdown/HTML content, resolved to absolute file URLs.
    var imageURLs: [URL] {
        imageURLs(from: resolvedContent)
    }

    /// Extract image URLs from pre-loaded content (avoids redundant resolvedContent calls).
    func imageURLs(from text: String) -> [URL] {
        guard !text.isEmpty else { return [] }
        var urls: [URL] = []
        // Use the note's directory (parent of its file) for resolving relative image paths
        let baseURL = absoluteFileURL.deletingLastPathComponent()

        // Markdown images: ![alt](./.attachments/file.png) or ![alt](path)
        let mdMatches = Self.mdImageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in mdMatches {
            if let range = Range(match.range(at: 1), in: text) {
                let path = String(text[range])
                    .removingPercentEncoding ?? String(text[range])
                let resolved = resolveImagePath(path, base: baseURL)
                if let resolved { urls.append(resolved) }
            }
        }

        // HTML images: <img src="path">
        let htmlMatches = Self.htmlImageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in htmlMatches {
            if let range = Range(match.range(at: 1), in: text) {
                let path = String(text[range])
                    .removingPercentEncoding ?? String(text[range])
                let resolved = resolveImagePath(path, base: baseURL)
                if let resolved, !urls.contains(resolved) { urls.append(resolved) }
            }
        }

        return urls
    }

    /// Extract only note-owned attachment URLs that are safe to upload during sync.
    func attachmentImageURLs(from text: String) -> [URL] {
        let attachmentDir = absoluteFileURL.deletingLastPathComponent()
            .appendingPathComponent(".attachments", isDirectory: true)
        return imageURLs(from: text).filter {
            FileContainment.isContained($0, in: attachmentDir)
        }
    }

    /// Word count from plain text content (HTML stripped).
    var wordCount: Int {
        let plain = strippedContent
        guard !plain.isEmpty else { return 0 }
        var count = 0
        plain.enumerateSubstrings(in: plain.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Plain text preview for card display.
    var contentPreview: String {
        let plain = strippedContent
        guard !plain.isEmpty else { return "" }
        return String(plain.prefix(150))
    }

    // MARK: - Private Helpers

    private var strippedContent: String {
        let text = resolvedContent
        guard !text.isEmpty else { return "" }
        return text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[#*_~`>]+"#, with: "", options: .regularExpression)
            // Strip markdown hard breaks (trailing backslash before newline)
            .replacingOccurrences(of: #"\\\n"#, with: "\n", options: .regularExpression)
            // Strip any remaining lone backslashes used as escapes
            .replacingOccurrences(of: #"\\"#, with: "")
            // Collapse runs of 3+ newlines to a single blank line
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            // Collapse inline whitespace (spaces/tabs) but leave newlines alone
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveImagePath(_ path: String, base: URL) -> URL? {
        func existingContainedURL(_ url: URL, allowedRoots: [URL]) -> URL? {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path),
                  FileContainment.isContained(standardized, inAny: allowedRoots) else {
                return nil
            }
            return standardized
        }

        let attachmentDir = base.appendingPathComponent(".attachments", isDirectory: true)
        let allowedRoots = [base, attachmentDir]

        if path.hasPrefix("cider-vault://"),
           let url = URL(string: path) {
            return existingContainedURL(URL(fileURLWithPath: url.path), allowedRoots: allowedRoots)
        }
        if path.hasPrefix("file:///") {
            let posixPath = String(path.dropFirst("file://".count))
            return existingContainedURL(URL(fileURLWithPath: posixPath), allowedRoots: allowedRoots)
        }
        if path.hasPrefix("./") {
            let relative = String(path.dropFirst(2))
            return existingContainedURL(base.appendingPathComponent(relative), allowedRoots: allowedRoots)
        }
        if path.hasPrefix(".attachments/") {
            return existingContainedURL(base.appendingPathComponent(path), allowedRoots: [attachmentDir])
        }
        if path.hasPrefix("/") {
            return existingContainedURL(URL(fileURLWithPath: path), allowedRoots: allowedRoots)
        }
        return nil
    }
}

struct ProjectPlanMetadata: Hashable {
    let type: String
    let status: String
    let category: String?
    let source: String?
    let dogfoodStatus: String?
    let parkedBecause: String?
    let revisitTrigger: String?

    var isIdeaPlan: Bool { type == "idea-plan" }
    var isParked: Bool { status == "parked" }
    var isTemplate: Bool { status == "template" }
    var isActive: Bool { !isParked && !isTemplate }

    init?(note: Note) {
        guard note.artifactType?.localizedLowercase == "plan",
              note.relativePath.localizedCaseInsensitiveContains("/Plans/") else {
            return nil
        }
        let fields = Self.frontmatterFields(in: note.content.isEmpty ? note.resolvedContent : note.content)
        let type = Self.normalized(fields["type"] ?? "plan")
        let status = Self.normalized(fields["status"] ?? "active")
        self.type = type.isEmpty ? "plan" : type
        self.status = status.isEmpty ? "active" : status
        self.category = Self.optionalNormalized(fields["category"])
        self.source = Self.optionalTrimmed(fields["source"])
        self.dogfoodStatus = Self.optionalNormalized(fields["dogfoodStatus"] ?? fields["dogfoodstatus"])
        self.parkedBecause = Self.optionalTrimmed(fields["parkedBecause"] ?? fields["parkedbecause"])
        self.revisitTrigger = Self.optionalTrimmed(fields["revisitTrigger"] ?? fields["revisittrigger"])
    }

    private static func frontmatterFields(in content: String) -> [String: String] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") || normalized == "---" else { return [:] }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return [:] }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            if line == "---" { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            fields[key] = unquoted(rawValue)
        }
        return fields
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private static func optionalNormalized(_ value: String?) -> String? {
        guard let normalized = value.map(normalized), !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func optionalTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Cached Display Data

/// Pre-computed display data for a note card/row. Computed once off the main
/// render path so views don't hit disk or run regex on every SwiftUI layout pass.
struct NoteCardData: Equatable {
    let preview: String
    let wordCount: Int
    let imageURLs: [URL]
    /// Downsampled thumbnail images keyed by URL, ready to display.
    let thumbnails: [URL: NSImage]

    static let empty = NoteCardData(preview: "", wordCount: 0, imageURLs: [], thumbnails: [:])

    static func load(for note: Note) -> NoteCardData {
        // Resolve content once — avoids 3x CiderConfig.load() + disk I/O
        let raw = note.resolvedContent
        let stripped = Self.stripMarkup(raw)
        let preview = String(stripped.prefix(150))
        let wordCount = Self.countWords(stripped)
        let imageURLs = note.imageURLs(from: raw)

        var thumbnails: [URL: NSImage] = [:]
        for url in imageURLs.prefix(3) {
            if let image = downsampledImage(at: url, maxDimension: 240) {
                thumbnails[url] = image
            }
        }

        return NoteCardData(
            preview: preview,
            wordCount: wordCount,
            imageURLs: imageURLs,
            thumbnails: thumbnails
        )
    }

    static func stripMarkup(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[#*_~`>]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\\"#, with: "")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func countWords(_ plain: String) -> Int {
        guard !plain.isEmpty else { return 0 }
        var count = 0
        plain.enumerateSubstrings(in: plain.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func downsampledImage(at url: URL, maxDimension: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - NoteCardData Cache

/// Cross-view cache for NoteCardData. Keyed by note ID + modifiedAt so that
/// switching tabs or scrolling cards back into view doesn't re-fetch from disk.
/// Access only from main actor (inside `.task` closures).
@MainActor
enum NoteCardDataCache {
    private static var entries: [UUID: (modifiedAt: Date, data: NoteCardData)] = [:]

    static func get(noteID: UUID, modifiedAt: Date) -> NoteCardData? {
        guard let entry = entries[noteID], entry.modifiedAt == modifiedAt else { return nil }
        return entry.data
    }

    static func set(_ data: NoteCardData, noteID: UUID, modifiedAt: Date) {
        entries[noteID] = (modifiedAt, data)
    }

    static func invalidate(noteID: UUID) {
        entries.removeValue(forKey: noteID)
    }

    static func invalidateAll() {
        entries.removeAll()
    }
}

// MARK: - Date Formatting

extension Date {
    /// Shows relative time for dates within 14 days ("2 hours ago", "yesterday",
    /// "2 weeks ago"), then switches to an absolute date ("Feb 1, 2026").
    var noteCardDate: String {
        let daysSince = Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
        if daysSince <= 14 {
            return formatted(.relative(presentation: .named))
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}
