import Foundation

enum NotesMarkdownPathCodec {
    /// Convert stored markdown to editor-friendly markdown (absolute image paths).
    static func markdownForEditor(_ markdown: String, notesDirectoryURL: URL) -> String {
        var normalized = markdown
        let encodedDirectoryPath = notesDirectoryURL.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? notesDirectoryURL.path
        let absolutePrefix = encodedDirectoryPath + "/"

        normalized = normalized.replacingOccurrences(of: "(./", with: "(\(absolutePrefix)")
        normalized = normalized.replacingOccurrences(of: "=\"./", with: "=\"\(absolutePrefix)")
        normalized = normalized.replacingOccurrences(of: "('./", with: "('\(absolutePrefix)")

        normalized = normalized.replacingOccurrences(
            of: "(.attachments/",
            with: "(\(absolutePrefix).attachments/"
        )
        normalized = normalized.replacingOccurrences(
            of: "=\".attachments/",
            with: "=\"\(absolutePrefix).attachments/"
        )
        normalized = normalized.replacingOccurrences(
            of: "('.attachments/",
            with: "('\(absolutePrefix).attachments/"
        )

        return normalized
    }

    /// Convert editor markdown to portable markdown (relative image paths).
    static func markdownForPersistence(_ markdown: String, notesDirectoryURL: URL) -> String {
        var normalized = markdown
        let rawPrefix = notesDirectoryURL.path + "/"
        let encodedPrefix = (
            notesDirectoryURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? notesDirectoryURL.path
        ) + "/"

        normalized = normalized.replacingOccurrences(of: "(\(rawPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(rawPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(rawPrefix)", with: "('./")

        normalized = normalized.replacingOccurrences(of: "(\(encodedPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(encodedPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(encodedPrefix)", with: "('./")

        let fileRawPrefix = "file://\(rawPrefix)"
        let fileEncodedPrefix = "file://\(encodedPrefix)"

        normalized = normalized.replacingOccurrences(of: "(\(fileRawPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(fileRawPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(fileRawPrefix)", with: "('./")

        normalized = normalized.replacingOccurrences(of: "(\(fileEncodedPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(fileEncodedPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(fileEncodedPrefix)", with: "('./")

        // Portability fallback: normalize legacy absolute attachment paths from
        // other machines/folders into relative paths.
        normalized = normalizeLegacyAbsoluteAttachmentPaths(normalized)

        return normalized
    }

    private static func normalizeLegacyAbsoluteAttachmentPaths(_ markdown: String) -> String {
        var normalized = markdown

        // Markdown links/images: (.../.attachments/<file>)
        normalized = normalized.replacingOccurrences(
            of: #"\((?:file://)?/[^\)]*?/\.attachments/"#,
            with: "(./.attachments/",
            options: .regularExpression
        )

        // HTML attributes: src="/.../.attachments/<file>"
        normalized = normalized.replacingOccurrences(
            of: #"=\"(?:file://)?/[^\"]*?/\.attachments/"#,
            with: "=\"./.attachments/",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"='(?:file://)?/[^']*?/\.attachments/"#,
            with: "='./.attachments/",
            options: .regularExpression
        )

        return normalized
    }
}
