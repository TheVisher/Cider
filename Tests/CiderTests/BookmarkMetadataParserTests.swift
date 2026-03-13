import Foundation
import Testing
@testable import Cider

@Suite("Bookmark Metadata Parser Tests")
struct BookmarkMetadataParserTests {

    let exampleURL = URL(string: "https://example.com/page")!

    // MARK: - Title Extraction

    @Test("Extracts og:title")
    func ogTitle() {
        let html = """
        <html><head>
        <meta property="og:title" content="OG Title Here">
        <title>Fallback Title</title>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "OG Title Here")
    }

    @Test("Falls back to twitter:title when og:title missing")
    func twitterTitle() {
        let html = """
        <html><head>
        <meta name="twitter:title" content="Twitter Card Title">
        <title>Fallback</title>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Twitter Card Title")
    }

    @Test("Falls back to title tag when no meta titles")
    func titleTag() {
        let html = """
        <html><head><title>  Page Title  </title></head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Page Title")
    }

    @Test("Extracts title from JSON-LD")
    func jsonLDTitle() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@type": "Article", "headline": "JSON-LD Headline"}
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "JSON-LD Headline")
    }

    @Test("Prefers og:title over JSON-LD and title tag")
    func titlePriority() {
        let html = """
        <html><head>
        <meta property="og:title" content="OG Wins">
        <script type="application/ld+json">{"headline": "LD Title"}</script>
        <title>Tag Title</title>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "OG Wins")
    }

    @Test("Returns no title for empty HTML but still finds default favicon")
    func emptyHTML() {
        let result = BookmarkMetadataParser.parse(html: "", pageURL: exampleURL)
        #expect(result?.title == nil)
        #expect(result?.thumbnailURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test("Returns no title when only whitespace title")
    func whitespaceTitle() {
        let html = "<html><head><title>   </title></head></html>"
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == nil)
    }

    // MARK: - Thumbnail Extraction

    @Test("Extracts og:image URL")
    func ogImage() {
        let html = """
        <html><head>
        <meta property="og:title" content="Test">
        <meta property="og:image" content="https://cdn.example.com/image.jpg">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://cdn.example.com/image.jpg")
    }

    @Test("Extracts twitter:image URL")
    func twitterImage() {
        let html = """
        <html><head>
        <meta name="twitter:title" content="Test">
        <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://cdn.example.com/twitter.jpg")
    }

    @Test("Resolves relative og:image against page URL")
    func relativeImage() {
        let html = """
        <html><head>
        <meta property="og:title" content="Test">
        <meta property="og:image" content="/images/hero.png">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://example.com/images/hero.png")
    }

    @Test("Extracts image from JSON-LD")
    func jsonLDImage() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@type": "Article", "headline": "Test", "image": "https://cdn.example.com/ld-image.jpg"}
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://cdn.example.com/ld-image.jpg")
    }

    @Test("Falls back to favicon when no og:image")
    func faviconFallback() {
        let html = """
        <html><head>
        <title>Test Page</title>
        <link rel="icon" href="/favicon.ico">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://example.com/favicon.ico")
    }

    @Test("Prefers apple-touch-icon over shortcut icon")
    func faviconPriority() {
        let html = """
        <html><head>
        <title>Test</title>
        <link rel="shortcut icon" href="/favicon.ico">
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://example.com/apple-touch-icon.png")
    }

    @Test("Default favicon.ico when no link tags")
    func defaultFavicon() {
        let html = "<html><head><title>Test</title></head></html>"
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://example.com/favicon.ico")
    }

    // MARK: - Site-Specific Behavior

    @Test("Reddit: skips placeholder images")
    func redditPlaceholder() {
        let redditURL = URL(string: "https://www.reddit.com/r/swift/comments/abc123/test")!
        let html = """
        <html><head>
        <meta property="og:title" content="Reddit Post">
        <meta property="og:image" content="https://preview.redd.it/if-you-are-looking-for-an-image.png">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: redditURL)
        // Should have title but skip the placeholder image
        #expect(result?.title == "Reddit Post")
        #expect(result?.thumbnailURL == nil)
    }

    @Test("Reddit: accepts real redd.it images")
    func redditRealImage() {
        let redditURL = URL(string: "https://www.reddit.com/r/swift/comments/abc123/test")!
        let html = """
        <html><head>
        <meta property="og:title" content="Reddit Post">
        </head><body>
        https://i.redd.it/realphoto123.jpg
        </body></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: redditURL)
        #expect(result?.thumbnailURL?.host == "i.redd.it")
    }

    @Test("X/Twitter: no favicon fallback")
    func xNoFavicon() {
        let xURL = URL(string: "https://x.com/user/status/123")!
        let html = """
        <html><head>
        <meta property="og:title" content="Tweet">
        <link rel="icon" href="/favicon.ico">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: xURL)
        #expect(result?.title == "Tweet")
        // X is excluded from favicon fallback
        #expect(result?.thumbnailURL == nil)
    }

    @Test("X/Twitter: extracts twimg media URL")
    func xTwimgImage() {
        let xURL = URL(string: "https://x.com/user/status/123")!
        let html = """
        <html><head>
        <meta property="og:title" content="Tweet">
        </head><body>
        https://pbs.twimg.com/media/ABC123.jpg
        </body></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: xURL)
        #expect(result?.thumbnailURL?.host == "pbs.twimg.com")
    }

    // MARK: - HTML Entity Decoding

    @Test("Decodes named HTML entities in titles")
    func namedEntities() {
        let html = """
        <html><head><title>Tom &amp; Jerry &mdash; The Movie</title></head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Tom & Jerry \u{2014} The Movie")
    }

    @Test("Decodes numeric HTML entities")
    func numericEntities() {
        let html = """
        <html><head><title>Price: &#36;100 &#x2014; Sale</title></head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Price: $100 \u{2014} Sale")
    }

    @Test("Decodes entities in meta content")
    func metaEntities() {
        let html = """
        <html><head>
        <meta property="og:title" content="Ben &amp; Jerry&#39;s">
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Ben & Jerry's")
    }

    // MARK: - JSON-LD Edge Cases

    @Test("Handles JSON-LD with CDATA wrapper")
    func jsonLDCDATA() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        <![CDATA[{"headline": "CDATA Title"}]]>
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "CDATA Title")
    }

    @Test("Handles JSON-LD with trailing semicolon")
    func jsonLDTrailingSemicolon() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"headline": "Semicolon Title"};
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.title == "Semicolon Title")
    }

    @Test("Extracts nested image URL from JSON-LD object")
    func jsonLDNestedImage() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@type": "Article", "headline": "Test", "image": {"url": "https://cdn.example.com/nested.jpg"}}
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://cdn.example.com/nested.jpg")
    }

    @Test("Extracts image from JSON-LD array")
    func jsonLDArrayImage() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@type": "Article", "headline": "Test", "image": ["https://cdn.example.com/first.jpg", "https://cdn.example.com/second.jpg"]}
        </script>
        </head></html>
        """
        let result = BookmarkMetadataParser.parse(html: html, pageURL: exampleURL)
        #expect(result?.thumbnailURL?.absoluteString == "https://cdn.example.com/first.jpg")
    }

    // MARK: - oEmbed

    @Test("Generates oEmbed endpoint for TikTok")
    func oEmbedTikTok() {
        let tiktokURL = URL(string: "https://www.tiktok.com/@user/video/123")!
        let endpoint = BookmarkMetadataParser.oEmbedEndpointURL(for: tiktokURL)
        #expect(endpoint?.host == "www.tiktok.com")
        #expect(endpoint?.path == "/oembed")
    }

    @Test("Generates oEmbed endpoint for Instagram")
    func oEmbedInstagram() {
        let igURL = URL(string: "https://www.instagram.com/p/ABC123/")!
        let endpoint = BookmarkMetadataParser.oEmbedEndpointURL(for: igURL)
        #expect(endpoint?.host == "api.instagram.com")
    }

    @Test("Generates oEmbed endpoint for Spotify")
    func oEmbedSpotify() {
        let spotifyURL = URL(string: "https://open.spotify.com/track/abc")!
        let endpoint = BookmarkMetadataParser.oEmbedEndpointURL(for: spotifyURL)
        #expect(endpoint?.host == "open.spotify.com")
    }

    @Test("Returns nil oEmbed for unsupported sites")
    func oEmbedUnsupported() {
        let endpoint = BookmarkMetadataParser.oEmbedEndpointURL(for: exampleURL)
        #expect(endpoint == nil)
    }

    // MARK: - Normalized Host

    @Test("Strips www. prefix")
    func normalizedHostWWW() {
        let url = URL(string: "https://www.example.com/page")!
        #expect(BookmarkMetadataParser.normalizedHost(for: url) == "example.com")
    }

    @Test("Strips m. prefix")
    func normalizedHostMobile() {
        let url = URL(string: "https://m.reddit.com/r/swift")!
        #expect(BookmarkMetadataParser.normalizedHost(for: url) == "reddit.com")
    }

    @Test("Leaves bare host unchanged")
    func normalizedHostBare() {
        let url = URL(string: "https://example.com/page")!
        #expect(BookmarkMetadataParser.normalizedHost(for: url) == "example.com")
    }

    // MARK: - decodeHTMLEntities

    @Test("Decodes all named entities")
    func allNamedEntities() {
        let input = "&quot;hello&quot; &amp; &lt;world&gt; &apos;test&apos;"
        let result = BookmarkMetadataParser.decodeHTMLEntities(input)
        #expect(result == "\"hello\" & <world> 'test'")
    }

    @Test("Decodes mixed numeric and named entities")
    func mixedEntities() {
        let input = "&#169; 2026 &mdash; All rights &#x2122;"
        let result = BookmarkMetadataParser.decodeHTMLEntities(input)
        #expect(result == "\u{00A9} 2026 \u{2014} All rights \u{2122}")
    }

    @Test("Passes through plain text unchanged")
    func plainText() {
        let input = "Just a normal string"
        let result = BookmarkMetadataParser.decodeHTMLEntities(input)
        #expect(result == "Just a normal string")
    }
}
