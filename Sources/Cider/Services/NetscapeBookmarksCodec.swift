import Foundation

enum NetscapeBookmarksCodec {
    private static let anchorRegex = try? NSRegularExpression(
        pattern: #"(?is)<a\b([^>]*)>(.*?)</a>"#,
        options: []
    )
    private static let hrefRegex = try? NSRegularExpression(
        pattern: #"(?is)\bhref\s*=\s*(['"])(.*?)\1"#,
        options: []
    )
    private static let addDateRegex = try? NSRegularExpression(
        pattern: #"(?is)\badd_date\s*=\s*(['"])(\d+)\1"#,
        options: []
    )
    private static let lastModifiedRegex = try? NSRegularExpression(
        pattern: #"(?is)\blast_modified\s*=\s*(['"])(\d+)\1"#,
        options: []
    )

    struct Entry {
        let urlString: String
        let title: String?
        let addDate: Date?
        let lastModified: Date?
    }

    static func decode(_ html: String) -> [Entry] {
        guard let anchorRegex,
              let hrefRegex,
              let addDateRegex,
              let lastModifiedRegex else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = anchorRegex.matches(in: html, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(matches.count)

        for match in matches {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = String(html[attrsRange])
            guard let href = firstCapture(of: hrefRegex, in: attributes, group: 2)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty else {
                continue
            }

            let addDate = unixDate(from: firstCapture(of: addDateRegex, in: attributes, group: 2))
            let lastModified = unixDate(from: firstCapture(of: lastModifiedRegex, in: attributes, group: 2))
            let titleRaw = String(html[titleRange])
            let decodedTitle = BookmarkMetadataParser.decodeHTMLEntities(titleRaw).trimmingCharacters(in: .whitespacesAndNewlines)

            entries.append(
                Entry(
                    urlString: BookmarkMetadataParser.decodeHTMLEntities(href),
                    title: decodedTitle.isEmpty ? nil : decodedTitle,
                    addDate: addDate,
                    lastModified: lastModified
                )
            )
        }

        return entries
    }

    static func encode(_ bookmarks: [Bookmark]) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file.",
            "     It will be read and overwritten.",
            "     DO NOT EDIT! -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]

        for bookmark in bookmarks {
            let escapedURL = escapeHTMLAttribute(bookmark.urlString)
            let escapedTitle = escapeHTMLText(bookmark.title)
            let addDate = Int(bookmark.createdAt.timeIntervalSince1970)
            let lastModified = Int(bookmark.updatedAt.timeIntervalSince1970)
            lines.append(
                "    <DT><A HREF=\"\(escapedURL)\" ADD_DATE=\"\(addDate)\" LAST_MODIFIED=\"\(lastModified)\">\(escapedTitle)</A>"
            )
        }

        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    private static func firstCapture(of regex: NSRegularExpression, in string: String, group: Int) -> String? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let valueRange = Range(match.range(at: group), in: string) else {
            return nil
        }
        return String(string[valueRange])
    }

    private static func unixDate(from value: String?) -> Date? {
        guard let value, let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func escapeHTMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTMLText(value)
    }
}
