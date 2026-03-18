import Foundation

enum NotesMarkdownPathCodec {
    /// Convert stored markdown to editor-friendly markdown.
    /// Attachment paths are rewritten to use the `cider-vault://` custom scheme so
    /// WKWebView can load them without needing broad filesystem `allowingReadAccessTo`.
    static func markdownForEditor(_ markdown: String, notesDirectoryURL: URL) -> String {
        var normalized = markdown
        let encodedDirectoryPath = notesDirectoryURL.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? notesDirectoryURL.path
        let schemePrefix = "cider-vault://" + encodedDirectoryPath + "/"

        normalized = normalized.replacingOccurrences(of: "(./", with: "(\(schemePrefix)")
        normalized = normalized.replacingOccurrences(of: "=\"./", with: "=\"\(schemePrefix)")
        normalized = normalized.replacingOccurrences(of: "('./", with: "('\(schemePrefix)")

        normalized = normalized.replacingOccurrences(
            of: "(.attachments/",
            with: "(\(schemePrefix).attachments/"
        )
        normalized = normalized.replacingOccurrences(
            of: "=\".attachments/",
            with: "=\"\(schemePrefix).attachments/"
        )
        normalized = normalized.replacingOccurrences(
            of: "('.attachments/",
            with: "('\(schemePrefix).attachments/"
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

        // Strip cider-vault:// scheme paths (current editor format)
        let vaultSchemeRawPrefix = "cider-vault://\(rawPrefix)"
        let vaultSchemeEncodedPrefix = "cider-vault://\(encodedPrefix)"

        normalized = normalized.replacingOccurrences(of: "(\(vaultSchemeRawPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(vaultSchemeRawPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(vaultSchemeRawPrefix)", with: "('./")

        normalized = normalized.replacingOccurrences(of: "(\(vaultSchemeEncodedPrefix)", with: "(./")
        normalized = normalized.replacingOccurrences(of: "=\"\(vaultSchemeEncodedPrefix)", with: "=\"./")
        normalized = normalized.replacingOccurrences(of: "('\(vaultSchemeEncodedPrefix)", with: "('./")

        // Strip plain absolute paths (legacy, pre-cider-vault scheme)
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

        // Markdown links/images: (.../.attachments/<file>) — covers file:// and cider-vault://
        normalized = normalized.replacingOccurrences(
            of: #"\((?:cider-vault://|file://)?/[^\)]*?/\.attachments/"#,
            with: "(./.attachments/",
            options: .regularExpression
        )

        // HTML attributes: src="/.../.attachments/<file>" — covers file:// and cider-vault://
        normalized = normalized.replacingOccurrences(
            of: #"=\"(?:cider-vault://|file://)?/[^\"]*?/\.attachments/"#,
            with: "=\"./.attachments/",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"='(?:cider-vault://|file://)?/[^']*?/\.attachments/"#,
            with: "='./.attachments/",
            options: .regularExpression
        )

        return normalized
    }
}
