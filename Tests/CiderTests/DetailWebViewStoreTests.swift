import Foundation
import Testing
import WebKit
@testable import Cider

@MainActor
struct DetailWebViewStoreTests {
    @Test("web view instance is reused across bookmark changes")
    func webViewInstanceIsReusedAcrossBookmarkChanges() throws {
        let store = DetailWebViewStore()
        let firstURL = try #require(URL(string: "https://example.com/one"))
        let secondURL = try #require(URL(string: "https://example.com/two"))

        store.ensureWebViewLoaded(url: firstURL)
        let firstWebView = try #require(store.webView)

        store.prepareForBookmarkChange()
        store.ensureWebViewLoaded(url: secondURL)
        let secondWebView = try #require(store.webView)

        #expect(firstWebView === secondWebView)
    }

    @Test("reader web view instance is reused across bookmark changes")
    func readerWebViewInstanceIsReusedAcrossBookmarkChanges() throws {
        let store = DetailWebViewStore()
        let firstURL = try #require(URL(string: "https://example.com/one"))
        let secondURL = try #require(URL(string: "https://example.com/two"))
        let delegate = DummyNavigationDelegate()

        let firstReaderWebView = store.getReaderWebView(for: firstURL, delegate: delegate)

        store.prepareForBookmarkChange()
        let secondReaderWebView = store.getReaderWebView(for: secondURL, delegate: delegate)

        #expect(firstReaderWebView === secondReaderWebView)
    }
}

private final class DummyNavigationDelegate: NSObject, WKNavigationDelegate {}
