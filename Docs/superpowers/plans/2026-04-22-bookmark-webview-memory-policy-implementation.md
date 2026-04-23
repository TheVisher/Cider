# Bookmark Web View Memory Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user-configurable bookmark web-view memory policy that preserves the active bookmark page across panel dismiss while trimming auxiliary bookmark web-view RAM.

**Architecture:** Introduce a small persisted enum for the user preference, wire it into `CiderConfig` and the `General -> Panel` settings UI, then teach `DetailWebViewStore` to trim itself in two explicit modes: full reset or preserve-active-live-page. Finally, replace the current blanket `closeAllDetails()` behavior on panel dismiss with a bookmark-aware dismiss handler that preserves active bookmark detail state when the selected policy requires it, while leaving reminders, notifications, Telegram, and CLI/orchestrator services untouched in `AppDelegate`.

**Tech Stack:** Swift, SwiftUI, WebKit, Swift Testing, `swift test`

---

## File Structure

- Create: `Sources/Cider/Models/BookmarkWebViewMemoryPolicy.swift`
  Purpose: define the persisted user-facing memory policy enum and the dismiss action resolver used by the panel.
- Modify: `Sources/Cider/Models/CiderConfig.swift`
  Purpose: persist the new preference with backward-compatible default decoding.
- Modify: `Sources/Cider/ViewModels/SettingsViewModel.swift`
  Purpose: expose the new setting to the Settings UI and save it through `CiderConfig`.
- Modify: `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift`
  Purpose: add the picker under `General -> Panel`.
- Modify: `Sources/Cider/Services/DetailWebViewStore.swift`
  Purpose: add explicit trim modes so the store can preserve only the active live page or fully reset.
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
  Purpose: route panel dismiss through a bookmark-aware handler instead of always calling `closeAllDetails()`.
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
  Purpose: implement the dismiss handler that preserves bookmark detail state when appropriate and closes unrelated detail state.
- Modify: `Tests/CiderTests/CiderConfigBackwardCompatTests.swift`
  Purpose: verify default decoding and round-trip persistence for the new preference.
- Modify: `Tests/CiderTests/DetailWebViewStoreTests.swift`
  Purpose: verify the new trim modes preserve or reset the right `WKWebView` state.
- Create: `Tests/CiderTests/BookmarkWebViewMemoryPolicyTests.swift`
  Purpose: verify the policy-to-dismiss-action mapping independently from the SwiftUI panel.

### Task 1: Add the persisted memory policy and settings UI

**Files:**
- Create: `Sources/Cider/Models/BookmarkWebViewMemoryPolicy.swift`
- Modify: `Sources/Cider/Models/CiderConfig.swift`
- Modify: `Sources/Cider/ViewModels/SettingsViewModel.swift`
- Modify: `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift`
- Test: `Tests/CiderTests/CiderConfigBackwardCompatTests.swift`

- [ ] **Step 1: Write the failing config tests**

Add these tests to `Tests/CiderTests/CiderConfigBackwardCompatTests.swift`:

```swift
    @Test("Bookmark web view memory policy defaults to conserve memory when missing")
    func missingBookmarkWebViewMemoryPolicy() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(config.bookmarkWebViewMemoryPolicy == .conserveMemory)
    }

    @Test("Bookmark web view memory policy survives round-trip")
    func bookmarkWebViewMemoryPolicyRoundTrip() throws {
        var config = CiderConfig.default
        config.bookmarkWebViewMemoryPolicy = .keepMoreWarm

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CiderConfig.self, from: data)

        #expect(decoded.bookmarkWebViewMemoryPolicy == .keepMoreWarm)
    }
```

- [ ] **Step 2: Run the config tests to verify they fail**

Run: `swift test --filter CiderConfigBackwardCompatTests`

Expected: FAIL with errors that `CiderConfig` has no member `bookmarkWebViewMemoryPolicy` and the new enum type does not exist yet.

- [ ] **Step 3: Write the minimal implementation for the setting**

Create `Sources/Cider/Models/BookmarkWebViewMemoryPolicy.swift`:

```swift
import Foundation

enum BookmarkPanelDismissAction: Equatable {
    case fullReset
    case preserveActiveLivePage
    case keepWarm
}

enum BookmarkWebViewMemoryPolicy: String, Codable, CaseIterable {
    case conserveMemory
    case keepMoreWarm

    var displayName: String {
        switch self {
        case .conserveMemory:
            return "Conserve Memory"
        case .keepMoreWarm:
            return "Keep More Warm"
        }
    }

    var subtitle: String {
        switch self {
        case .conserveMemory:
            return "Keep only the active bookmark page warm after panel dismiss"
        case .keepMoreWarm:
            return "Keep bookmark detail web views warm for faster return"
        }
    }

    func dismissAction(hasOpenBookmarkDetail: Bool) -> BookmarkPanelDismissAction {
        switch self {
        case .conserveMemory:
            return hasOpenBookmarkDetail ? .preserveActiveLivePage : .fullReset
        case .keepMoreWarm:
            return .keepWarm
        }
    }
}
```

Modify `Sources/Cider/Models/CiderConfig.swift` in all four places where config fields are defined:

```swift
    private enum CodingKeys: String, CodingKey {
        case bookmarkWebViewMemoryPolicy
    }
```

```swift
    var bookmarkWebViewMemoryPolicy: BookmarkWebViewMemoryPolicy
```

```swift
            bookmarkWebViewMemoryPolicy: .conserveMemory,
```

```swift
        bookmarkWebViewMemoryPolicy = try container.decodeIfPresent(
            BookmarkWebViewMemoryPolicy.self,
            forKey: .bookmarkWebViewMemoryPolicy
        ) ?? .conserveMemory
```

```swift
        bookmarkWebViewMemoryPolicy: BookmarkWebViewMemoryPolicy = .conserveMemory,
```

```swift
        self.bookmarkWebViewMemoryPolicy = bookmarkWebViewMemoryPolicy
```

Modify `Sources/Cider/ViewModels/SettingsViewModel.swift`:

```swift
    @Published var bookmarkWebViewMemoryPolicy: BookmarkWebViewMemoryPolicy {
        didSet { saveConfig() }
    }
```

```swift
        self.bookmarkWebViewMemoryPolicy = config.bookmarkWebViewMemoryPolicy
```

```swift
        config.bookmarkWebViewMemoryPolicy = bookmarkWebViewMemoryPolicy
```

Modify `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift` inside the `case .panelBehavior:` section:

```swift
                    SettingsPickerRow(
                        title: "Bookmark web view memory",
                        subtitle: "How much bookmark detail state stays warm after panel dismiss",
                        selection: $viewModel.bookmarkWebViewMemoryPolicy,
                        options: BookmarkWebViewMemoryPolicy.allCases,
                        label: { $0.displayName }
                    )
```

- [ ] **Step 4: Run the config tests to verify they pass**

Run: `swift test --filter CiderConfigBackwardCompatTests`

Expected: PASS for the new memory-policy tests and the existing backward-compat suite.

- [ ] **Step 5: Commit the settings work**

```bash
git add Sources/Cider/Models/BookmarkWebViewMemoryPolicy.swift Sources/Cider/Models/CiderConfig.swift Sources/Cider/ViewModels/SettingsViewModel.swift Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift Tests/CiderTests/CiderConfigBackwardCompatTests.swift
git commit -m "Add bookmark webview memory setting"
```

### Task 2: Add explicit trim modes to `DetailWebViewStore`

**Files:**
- Modify: `Sources/Cider/Services/DetailWebViewStore.swift`
- Test: `Tests/CiderTests/DetailWebViewStoreTests.swift`

- [ ] **Step 1: Write the failing store tests**

Replace the current lightweight tests in `Tests/CiderTests/DetailWebViewStoreTests.swift` with these stronger cases:

```swift
import Foundation
import Testing
import WebKit
@testable import Cider

@MainActor
struct DetailWebViewStoreTests {
    @Test("preserve-active trim keeps the live bookmark page and drops reader state")
    func preserveActiveTrimKeepsLivePage() throws {
        let store = DetailWebViewStore()
        let url = try #require(URL(string: "https://example.com/article"))
        let delegate = DummyNavigationDelegate()

        store.ensureWebViewLoaded(url: url)
        let liveWebView = try #require(store.webView)
        _ = store.getReaderWebView(for: url, delegate: delegate)
        store.seedReaderWarmStateForTesting(
            article: .init(title: "Example", byline: "Author", content: "<p>Hello</p>"),
            url: url
        )

        store.trimForPanelDismiss(.preserveActiveLivePage)

        #expect(store.webView === liveWebView)
        #expect(store.readerWebView == nil)
        #expect(store.cachedArticle == nil)
        #expect(store.readerReady == false)
    }

    @Test("full reset drops both live and reader web views")
    func fullResetDropsAllWebViews() throws {
        let store = DetailWebViewStore()
        let url = try #require(URL(string: "https://example.com/article"))
        let delegate = DummyNavigationDelegate()

        store.ensureWebViewLoaded(url: url)
        _ = store.getReaderWebView(for: url, delegate: delegate)

        store.trimForPanelDismiss(.fullReset)

        #expect(store.webView == nil)
        #expect(store.readerWebView == nil)
        #expect(store.webViewReady == false)
        #expect(store.readerReady == false)
    }
}

private final class DummyNavigationDelegate: NSObject, WKNavigationDelegate {}
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run: `swift test --filter DetailWebViewStoreTests`

Expected: FAIL because `trimForPanelDismiss` and `seedReaderWarmStateForTesting` do not exist yet.

- [ ] **Step 3: Implement the trim modes with minimal store changes**

Add this nested enum and helper to `Sources/Cider/Services/DetailWebViewStore.swift`:

```swift
    enum PanelDismissTrimMode {
        case fullReset
        case preserveActiveLivePage
    }

    func trimForPanelDismiss(_ mode: PanelDismissTrimMode) {
        switch mode {
        case .fullReset:
            reset()
        case .preserveActiveLivePage:
            pauseMedia(in: readerWebView)
            readerWebView?.stopLoading()
            clearReusableContent(in: readerWebView)
            readerWebView = nil
            readerLoadedURL = nil
            cachedArticle = nil
            extractedArticleURL = nil
            readerReady = false
            readerFailed = false
            cancelReaderExtraction()
        }
    }
```

Add a small test helper inside the same type so the tests can seed reader warm state without relying on networked extraction:

```swift
    func seedReaderWarmStateForTesting(article: ReaderArticle, url: URL) {
        cachedArticle = article
        extractedArticleURL = url
        readerReady = true
    }
```

Do not change `prepareForBookmarkChange()` in this task. That method should continue to reuse the live `webView` across bookmark switches. The new trim method is only for panel dismiss.

- [ ] **Step 4: Run the store tests to verify they pass**

Run: `swift test --filter DetailWebViewStoreTests`

Expected: PASS, showing that preserve-active trim keeps the live page and full reset removes all bookmark-detail web-view state.

- [ ] **Step 5: Commit the store work**

```bash
git add Sources/Cider/Services/DetailWebViewStore.swift Tests/CiderTests/DetailWebViewStoreTests.swift
git commit -m "Add bookmark detail webview trim modes"
```

### Task 3: Wire panel dismiss through the new policy without disturbing background services

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Create: `Tests/CiderTests/BookmarkWebViewMemoryPolicyTests.swift`

- [ ] **Step 1: Write the failing policy resolver tests**

Create `Tests/CiderTests/BookmarkWebViewMemoryPolicyTests.swift`:

```swift
import Testing
@testable import Cider

@Suite("Bookmark Web View Memory Policy Tests")
struct BookmarkWebViewMemoryPolicyTests {
    @Test("Conserve Memory preserves the active page when bookmark detail is open")
    func conserveMemoryWithOpenBookmarkDetail() {
        let action = BookmarkWebViewMemoryPolicy.conserveMemory.dismissAction(
            hasOpenBookmarkDetail: true
        )

        #expect(action == .preserveActiveLivePage)
    }

    @Test("Conserve Memory fully resets when no bookmark detail is open")
    func conserveMemoryWithoutBookmarkDetail() {
        let action = BookmarkWebViewMemoryPolicy.conserveMemory.dismissAction(
            hasOpenBookmarkDetail: false
        )

        #expect(action == .fullReset)
    }

    @Test("Keep More Warm keeps existing bookmark detail state warm")
    func keepMoreWarm() {
        let action = BookmarkWebViewMemoryPolicy.keepMoreWarm.dismissAction(
            hasOpenBookmarkDetail: true
        )

        #expect(action == .keepWarm)
    }
}
```

- [ ] **Step 2: Run the resolver tests to verify they pass and then write the integration change**

Run: `swift test --filter BookmarkWebViewMemoryPolicyTests`

Expected: PASS, because the resolver was added in Task 1. This confirms the panel can rely on that mapping before any SwiftUI lifecycle code changes.

- [ ] **Step 3: Replace blanket panel-dismiss cleanup with bookmark-aware cleanup**

In `Sources/Cider/Views/CiderPanelView.swift`, replace the dismiss receiver:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .dismissCiderPanel)) { _ in
            handlePanelDismiss()
        }
```

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, add the dismiss handler:

```swift
    func handlePanelDismiss() {
        let policy = CiderConfig.load().bookmarkWebViewMemoryPolicy
        let dismissAction = policy.dismissAction(hasOpenBookmarkDetail: isDetailOpen)

        if isDetailOpen {
            saveBookmarkDetails()
        }

        if isNoteDetailOpen {
            notesViewModel.flushSave()
            selectedNote = nil
            isEditingNoteTitle = false
        }

        switch dismissAction {
        case .preserveActiveLivePage:
            detailWebViewStore.trimForPanelDismiss(.preserveActiveLivePage)
        case .fullReset:
            detailWebViewStore.trimForPanelDismiss(.fullReset)
            detailBookmarkID = nil
            detailsDraft = nil
        case .keepWarm:
            break
        }

        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil

        if !isDetailOpen {
            AIAssistantViewModel.shared.clearContext()
        }
    }
```

Important implementation rule for this step:

- when bookmark detail is open and the dismiss action is `.preserveActiveLivePage` or `.keepWarm`, do **not** clear `detailBookmarkID` or `detailsDraft`
- when there is no bookmark detail open, the dismiss path should still clear bookmark-detail state
- do **not** modify `AppDelegate.swift` startup services or `AppDelegate+CiderPanel.swift` background-service behavior in this task

- [ ] **Step 4: Run the targeted verification commands**

Run these commands:

```bash
swift test --filter BookmarkWebViewMemoryPolicyTests
swift test --filter DetailWebViewStoreTests
swift test --filter CiderConfigBackwardCompatTests
```

Expected:

- `BookmarkWebViewMemoryPolicyTests`: PASS
- `DetailWebViewStoreTests`: PASS
- `CiderConfigBackwardCompatTests`: PASS

- [ ] **Step 5: Commit the dismiss-path wiring**

```bash
git add Sources/Cider/Views/CiderPanelView.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Tests/CiderTests/BookmarkWebViewMemoryPolicyTests.swift
git commit -m "Trim bookmark webviews on panel dismiss"
```

### Task 4: Manual verification and polish

**Files:**
- Modify: no additional source files unless a manual bug is found

- [ ] **Step 1: Build and run the app locally**

Run: `swift build`

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify conserve-memory behavior manually**

Manual flow:

1. Set `General -> Panel -> Bookmark web view memory` to `Conserve Memory`.
2. Open a bookmark detail that uses the live web view.
3. Scroll the page somewhere obvious.
4. Dismiss the Cider panel.
5. Reopen the Cider panel.

Expected:

- the same bookmark detail is still open
- the live page has not refreshed
- scroll/session state is still intact
- reader warm state is not retained

- [ ] **Step 3: Verify full reset when no bookmark detail is open**

Manual flow:

1. Close any bookmark detail so only the library/folder view is visible.
2. Dismiss the panel.
3. Reopen the panel.

Expected:

- no bookmark detail state is preserved
- bookmark-detail web-view state has been fully reset

- [ ] **Step 4: Verify the warm mode and background-service boundary**

Manual flow:

1. Set `Bookmark web view memory` to `Keep More Warm`.
2. Open a bookmark detail and dismiss/reopen the panel.
3. While the panel is hidden, confirm reminders, notifications, Telegram delivery, and AI assistant/CLI behavior still work normally.

Expected:

- warm bookmark behavior is preserved in `Keep More Warm`
- hiding the panel does not stop background services started from `AppDelegate`

- [ ] **Step 5: Commit any tiny manual-fix follow-up**

```bash
git add -A
git commit -m "Polish bookmark webview memory behavior"
```

## Self-Review

### Spec coverage

- User-facing setting under `General -> Panel`: covered by Task 1.
- Persisted config with safe default: covered by Task 1.
- Preserve active live bookmark page on panel dismiss: covered by Tasks 2 and 3.
- Full reset when no bookmark detail is open: covered by Tasks 2 and 3.
- Leave notes out of scope for memory policy: handled in Task 3 by only flushing and closing note detail, not adding a notes memory policy.
- Keep reminders, notifications, Telegram, and CLI/orchestrator untouched: explicitly constrained in Task 3 and manually verified in Task 4.

### Placeholder scan

- No `TODO`, `TBD`, or implicit “handle edge cases later” wording remains.
- Each code-changing step includes concrete code snippets.
- Each verification step includes exact commands and expected outcomes.

### Type consistency

- Setting type: `BookmarkWebViewMemoryPolicy`
- Resolver result type: `BookmarkPanelDismissAction`
- Store trim API: `trimForPanelDismiss(_:)`
- Preserve-active trim case: `.preserveActiveLivePage`
- Full reset trim case: `.fullReset`

