import Foundation
import Testing
@testable import Cider

@Suite("Netscape Bookmarks Codec Tests")
struct NetscapeBookmarksCodecTests {

    // MARK: - Decode

    @Test("Decodes standard Netscape bookmark HTML")
    func decodesStandardBookmarks() {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1700000000" LAST_MODIFIED="1700100000">Example</A>
            <DT><A HREF="https://swift.org" ADD_DATE="1700200000">Swift</A>
        </DL><p>
        """

        let entries = NetscapeBookmarksCodec.decode(html)
        #expect(entries.count == 2)

        #expect(entries[0].urlString == "https://example.com")
        #expect(entries[0].title == "Example")
        #expect(entries[0].addDate == Date(timeIntervalSince1970: 1700000000))
        #expect(entries[0].lastModified == Date(timeIntervalSince1970: 1700100000))

        #expect(entries[1].urlString == "https://swift.org")
        #expect(entries[1].title == "Swift")
        #expect(entries[1].addDate == Date(timeIntervalSince1970: 1700200000))
        #expect(entries[1].lastModified == nil)
    }

    @Test("Skips entries with empty href")
    func skipsEmptyHref() {
        let html = """
        <DL><p>
            <DT><A HREF="" ADD_DATE="1700000000">Empty URL</A>
            <DT><A HREF="https://valid.com">Valid</A>
        </DL><p>
        """

        let entries = NetscapeBookmarksCodec.decode(html)
        #expect(entries.count == 1)
        #expect(entries[0].urlString == "https://valid.com")
    }

    @Test("Decodes HTML entities in URL and title")
    func decodesHTMLEntities() {
        let html = """
        <DL><p>
            <DT><A HREF="https://example.com/search?q=hello&amp;lang=en">Quotes &amp; &#39;Apostrophes&#39; &lt;Tags&gt;</A>
        </DL><p>
        """

        let entries = NetscapeBookmarksCodec.decode(html)
        #expect(entries.count == 1)
        #expect(entries[0].urlString == "https://example.com/search?q=hello&lang=en")
        #expect(entries[0].title == "Quotes & 'Apostrophes' <Tags>")
    }

    @Test("Handles missing title gracefully")
    func handlesMissingTitle() {
        let html = """
        <DL><p>
            <DT><A HREF="https://example.com">   </A>
        </DL><p>
        """

        let entries = NetscapeBookmarksCodec.decode(html)
        #expect(entries.count == 1)
        #expect(entries[0].title == nil)
    }

    @Test("Returns empty array for non-bookmark HTML")
    func returnsEmptyForNonBookmarkHTML() {
        let entries = NetscapeBookmarksCodec.decode("<html><body>No bookmarks here</body></html>")
        #expect(entries.isEmpty)
    }

    @Test("Returns empty array for empty string")
    func returnsEmptyForEmptyString() {
        let entries = NetscapeBookmarksCodec.decode("")
        #expect(entries.isEmpty)
    }

    // MARK: - Encode

    @Test("Encodes bookmarks to valid Netscape HTML")
    func encodesBookmarks() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let bookmarks = [
            Bookmark(title: "Example", urlString: "https://example.com", createdAt: date, updatedAt: date),
        ]

        let html = NetscapeBookmarksCodec.encode(bookmarks)
        #expect(html.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        #expect(html.contains("<TITLE>Bookmarks</TITLE>"))
        #expect(html.contains("HREF=\"https://example.com\""))
        #expect(html.contains("ADD_DATE=\"1700000000\""))
        #expect(html.contains("LAST_MODIFIED=\"1700000000\""))
        #expect(html.contains(">Example</A>"))
    }

    @Test("Escapes special characters in encoded output")
    func escapesSpecialCharacters() {
        let bookmarks = [
            Bookmark(title: "A & B <C> \"D\"", urlString: "https://example.com/q?a=1&b=2"),
        ]

        let html = NetscapeBookmarksCodec.encode(bookmarks)
        #expect(html.contains("HREF=\"https://example.com/q?a=1&amp;b=2\""))
        #expect(html.contains(">A &amp; B &lt;C&gt; &quot;D&quot;</A>"))
    }

    // MARK: - Round-trip

    @Test("Round-trip preserves URL and title")
    func roundTripPreservesData() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let original = [
            Bookmark(title: "Hello & World", urlString: "https://example.com/path?q=1&r=2", createdAt: date, updatedAt: date),
            Bookmark(title: "Swift Lang", urlString: "https://swift.org", createdAt: date, updatedAt: date),
        ]

        let html = NetscapeBookmarksCodec.encode(original)
        let decoded = NetscapeBookmarksCodec.decode(html)

        #expect(decoded.count == 2)
        #expect(decoded[0].urlString == "https://example.com/path?q=1&r=2")
        #expect(decoded[0].title == "Hello & World")
        #expect(decoded[1].urlString == "https://swift.org")
        #expect(decoded[1].title == "Swift Lang")
    }

    @Test("Round-trip preserves dates")
    func roundTripPreservesDates() {
        let created = Date(timeIntervalSince1970: 1700000000)
        let updated = Date(timeIntervalSince1970: 1700100000)
        let bookmarks = [
            Bookmark(title: "Test", urlString: "https://test.com", createdAt: created, updatedAt: updated),
        ]

        let html = NetscapeBookmarksCodec.encode(bookmarks)
        let decoded = NetscapeBookmarksCodec.decode(html)

        #expect(decoded.count == 1)
        #expect(decoded[0].addDate == created)
        #expect(decoded[0].lastModified == updated)
    }
}
