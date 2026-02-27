import AppKit
import Foundation

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    /// Relative path within the notes directory (e.g. "My Note.md")
    var relativePath: String
    var labelIDs: [UUID]
    var folderID: UUID?

    init(id: UUID = UUID(), title: String, content: String = "", createdAt: Date = Date(), modifiedAt: Date = Date(), relativePath: String = "", labelIDs: [UUID] = [], folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.relativePath = relativePath
        self.labelIDs = labelIDs
        self.folderID = folderID
    }

    // MARK: - Computed Properties for Card Display

    /// The raw content to use for display — loads from disk if the in-memory field is empty.
    /// Internal so NoteCardData.load() can call it once and pass through.
    var resolvedContent: String {
        if !content.isEmpty { return content }
        guard !relativePath.isEmpty else { return "" }
        let fileURL = StoragePaths.cachedDirectoryURL(for: .notes).appendingPathComponent(relativePath)
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    // Pre-compiled regexes for image extraction
    private static let mdImageRegex = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^\)]+)\)"#)
    private static let htmlImageRegex = try! NSRegularExpression(pattern: #"<img\s[^>]*src=[\"']([^\"']+)[\"']"#, options: .caseInsensitive)

    /// Extract image URLs from markdown/HTML content, resolved to absolute file URLs.
    var imageURLs: [URL] {
        imageURLs(from: resolvedContent)
    }

    /// Extract image URLs from pre-loaded content (avoids redundant resolvedContent calls).
    func imageURLs(from text: String) -> [URL] {
        guard !text.isEmpty else { return [] }
        var urls: [URL] = []
        let baseURL = StoragePaths.cachedDirectoryURL(for: .notes)

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
            // Collapse runs of 3+ newlines to a single blank line
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            // Collapse inline whitespace (spaces/tabs) but leave newlines alone
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveImagePath(_ path: String, base: URL) -> URL? {
        if path.hasPrefix("file:///") {
            let posixPath = String(path.dropFirst("file://".count))
            let url = URL(fileURLWithPath: posixPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if path.hasPrefix("./") {
            let relative = String(path.dropFirst(2))
            let url = base.appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if path.hasPrefix(".attachments/") {
            let url = base.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
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
