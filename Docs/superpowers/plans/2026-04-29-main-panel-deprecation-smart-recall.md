# Main Panel Deprecation And Smart Recall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the old full-app NSPanel as a user-facing surface, keep normal Cider as the main app window, and make Option activation recall the last meaningful floating work panel.

**Architecture:** Treat "quick panel" as deprecated and route activation through a small recall coordinator. The coordinator records recallable `CiderFloatableSurface` values, toggles the last one when possible, and falls back to the normal main window. Reanchoring is a separate explicit panel action that opens the main window to the same item.

**Tech Stack:** Swift 6, AppKit `NSWindow`/`NSPanel`, SwiftUI, `NotificationCenter`, Swift Testing, Xcode app build.

---

## File Structure

- Create `Sources/Cider/App/CiderSurfaceRecallCoordinator.swift`
  - Owns "what should Option activation do?" logic.
  - Keeps recallable surfaces separate from temporary utility surfaces.
  - Has pure testable state plus small AppKit-facing helpers.

- Modify `Sources/Cider/App/CiderFloatingPanelManager.swift`
  - Record recallable surfaces on float and close/dock.
  - Expose visibility checks needed by Smart Recall.
  - Add reanchor request handling only if it belongs closer to panel ownership.

- Modify `Sources/Cider/App/AppDelegate.swift`
  - Change Option activation from `toggleCiderPanel()` to Smart Recall.
  - Stop configuring the old full-app `CiderPanel`.
  - Remove "Show Quick Panel" menu entries.
  - Add reanchor notification handling that opens/focuses the main window.

- Modify or delete `Sources/Cider/App/AppDelegate+CiderPanel.swift`
  - First make its public entry points route to Smart Recall/main window for compatibility.
  - After references are removed, delete or leave as a tiny deprecated shim for one commit.

- Modify `Sources/Cider/App/CiderSurfaceTransitionPolicy.swift`
  - Remove `quickPanel` as a target from the active transition model, or mark it deprecated only if deletion would create a large rename wave.

- Modify `Sources/Cider/Utilities/Constants.swift`
  - Add `reanchorCiderSurface` and `openCiderSurfaceInMainWindow`.
  - Keep old notification names only as compatibility aliases during the cleanup.

- Modify `Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift`
  - Pass an `onReanchor` action to floating item surfaces.

- Modify `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
  - Add a visible "Show in Cider" button to note/bookmark/contact/todo/date card floating panels.
  - Button posts a reanchor notification with the panel's `CiderFloatableSurface`.

- Modify `Sources/Cider/Views/CiderPanelView.swift`
  - Main-window instances observe `openCiderSurfaceInMainWindow`.

- Modify `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
  - Add `openSurfaceInMainWindow(_:)` to resolve a `CiderFloatableSurface` to the existing detail-opening methods.

- Modify `Sources/Cider/Views/CiderPanelView+TitleBar.swift`
  - Remove the main-window button that toggles the old quick panel.

- Modify `Sources/Cider/Views/CiderPanelView+KeyboardNavigation.swift`
  - Route close/minimize/maximize only through main-window behavior for `.mainWindow`.
  - Remove quick panel shortcuts when the old panel is gone.

- Modify `Sources/Cider/Views/Settings/SettingsComponents.swift`
  - Update shortcut text from "Toggle Cider panel" to "Recall last Cider surface".

- Modify `Sources/Cider/Views/Onboarding/OnboardingTabView.swift`
  - Update Option copy to describe recall/open behavior.

- Modify tests:
  - `Tests/CiderTests/CiderFloatableSurfaceTests.swift`
  - `Tests/CiderTests/CiderSurfaceTransitionPolicyTests.swift`
  - Add `Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift`

---

## Parallel Work Lanes

- **Agent A: Smart Recall Core**
  - Owns `CiderSurfaceRecallCoordinator.swift`, `CiderFloatingPanelManager.swift`, and recall tests.

- **Agent B: Reanchor UI And Main-Window Navigation**
  - Owns floating item view changes, reanchor notifications, and `CiderPanelView+DetailManagement.swift`.

- **Agent C: Old Quick Panel Deprecation**
  - Owns menu/status/settings/onboarding/titlebar/transition cleanup.
  - Should not delete shared `CiderPanelView` or `CiderPanelShell`.

- **Integrator: AppDelegate Wiring**
  - Owns final `AppDelegate.swift` and `AppDelegate+CiderPanel.swift` conflict resolution because all lanes may touch activation wiring.

---

### Task 1: Add Smart Recall State

**Files:**
- Create: `Sources/Cider/App/CiderSurfaceRecallCoordinator.swift`
- Test: `Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift`

- [ ] **Step 1: Write failing recallability tests**

```swift
import Testing
import Foundation
@testable import Cider

struct CiderSurfaceRecallCoordinatorTests {
    @Test("item surfaces are recallable and utility surfaces are ignored")
    func recallabilityFiltersUtilitySurfaces() {
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.note(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.bookmarkMetadata(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.contact(UUID())))
        #expect(CiderSurfaceRecallCoordinator.isRecallable(.todo(UUID())))
        #expect(!CiderSurfaceRecallCoordinator.isRecallable(.dropZone))
        #expect(!CiderSurfaceRecallCoordinator.isRecallable(.clipboard))
        #expect(!CiderSurfaceRecallCoordinator.isRecallable(.aiAssistant))
    }

    @Test("activation opens main window when no recallable surface exists")
    func activationFallsBackToMainWindow() {
        var coordinator = CiderSurfaceRecallCoordinator()
        #expect(coordinator.activationAction(isVisible: { _ in false }) == .openMainWindow)
    }

    @Test("activation restores the last recallable surface")
    func activationRestoresLastSurface() {
        let noteID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()
        coordinator.record(.note(noteID))
        #expect(coordinator.activationAction(isVisible: { _ in false }) == .show(.note(noteID)))
    }

    @Test("activation hides the visible recalled surface")
    func activationHidesVisibleSurface() {
        let todoID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()
        coordinator.record(.todo(todoID))
        #expect(coordinator.activationAction(isVisible: { $0 == .todo(todoID) }) == .hide(.todo(todoID)))
    }

    @Test("closing a recallable surface keeps it available for recall")
    func closedSurfaceRemainsRecallable() {
        let bookmarkID = UUID()
        var coordinator = CiderSurfaceRecallCoordinator()
        coordinator.record(.bookmarkMetadata(bookmarkID))
        coordinator.recordClosed(.bookmarkMetadata(bookmarkID))
        #expect(coordinator.activationAction(isVisible: { _ in false }) == .show(.bookmarkMetadata(bookmarkID)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CiderSurfaceRecallCoordinatorTests
```

Expected: compile failure because `CiderSurfaceRecallCoordinator` does not exist.

- [ ] **Step 3: Add minimal coordinator**

```swift
import Foundation

enum CiderSurfaceActivationAction: Equatable {
    case openMainWindow
    case show(CiderFloatableSurface)
    case hide(CiderFloatableSurface)
}

struct CiderSurfaceRecallCoordinator {
    private(set) var lastRecallableSurface: CiderFloatableSurface?

    static func isRecallable(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo:
            true
        case .clipboard, .aiAssistant, .dropZone:
            false
        }
    }

    mutating func record(_ surface: CiderFloatableSurface) {
        guard Self.isRecallable(surface) else { return }
        lastRecallableSurface = surface
    }

    mutating func recordClosed(_ surface: CiderFloatableSurface) {
        guard Self.isRecallable(surface) else { return }
        lastRecallableSurface = surface
    }

    func activationAction(isVisible: (CiderFloatableSurface) -> Bool) -> CiderSurfaceActivationAction {
        guard let surface = lastRecallableSurface else {
            return .openMainWindow
        }
        return isVisible(surface) ? .hide(surface) : .show(surface)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter CiderSurfaceRecallCoordinatorTests
```

Expected: all coordinator tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/App/CiderSurfaceRecallCoordinator.swift Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift
git commit -m "Add Cider surface recall coordinator"
```

---

### Task 2: Wire Smart Recall Into Floating Panel Manager

**Files:**
- Modify: `Sources/Cider/App/CiderFloatingPanelManager.swift`
- Test: `Tests/CiderTests/CiderFloatableSurfaceTests.swift`

- [ ] **Step 1: Write failing manager tests**

Add these tests to `CiderFloatableSurfaceTests`:

```swift
@Test("floating manager records recallable surfaces")
func floatingManagerRecordsRecallableSurfaces() {
    let manager = CiderFloatingPanelManager()
    let noteID = UUID()

    manager.recordRecallCandidate(.note(noteID))

    #expect(manager.recallCoordinator.lastRecallableSurface == .note(noteID))
}

@Test("floating manager ignores drop zone as recall candidate")
func floatingManagerIgnoresDropZoneRecall() {
    let manager = CiderFloatingPanelManager()

    manager.recordRecallCandidate(.dropZone)

    #expect(manager.recallCoordinator.lastRecallableSurface == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CiderFloatableSurfaceTests/floatingManager
```

Expected: compile failure because `recordRecallCandidate` and `recallCoordinator` do not exist.

- [ ] **Step 3: Add manager recall bookkeeping**

Add to `CiderFloatingPanelManager`:

```swift
private(set) var recallCoordinator = CiderSurfaceRecallCoordinator()

func recordRecallCandidate(_ surface: CiderFloatableSurface) {
    recallCoordinator.record(surface)
}

func recordClosedRecallCandidate(_ surface: CiderFloatableSurface) {
    recallCoordinator.recordClosed(surface)
}

func isVisible(_ surface: CiderFloatableSurface) -> Bool {
    panelsByKey[surface.stableKey]?.isVisible == true
}

func performSmartRecall(fallbackToMainWindow: () -> Void) {
    switch recallCoordinator.activationAction(isVisible: isVisible) {
    case .openMainWindow:
        fallbackToMainWindow()
    case .show(let surface):
        float(surface)
    case .hide(let surface):
        dock(surface)
    }
}
```

In `float(_:)`, call `recordRecallCandidate(surface)` before returning a new or reused panel.

In `dock(_:)` and `windowWillClose(_:)`, call `recordClosedRecallCandidate(surface)` before unregistering.

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter CiderFloatableSurfaceTests/floatingManager
swift test --filter CiderSurfaceRecallCoordinatorTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/App/CiderFloatingPanelManager.swift Tests/CiderTests/CiderFloatableSurfaceTests.swift
git commit -m "Track last recallable floating surface"
```

---

### Task 3: Replace Option Activation With Smart Recall

**Files:**
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/App/AppDelegate+CiderPanel.swift`

- [ ] **Step 1: Add the activation method**

Add this method to `AppDelegate`:

```swift
func performCiderActivation() {
    guard let floatingPanelManager else {
        transitionToCiderMainWindow()
        return
    }

    floatingPanelManager.performSmartRecall { [weak self] in
        self?.transitionToCiderMainWindow()
    }
}
```

- [ ] **Step 2: Route Option activation to Smart Recall**

Change `startDoubleTapDetection()` from:

```swift
self?.toggleCiderPanel()
```

to:

```swift
self?.performCiderActivation()
```

This preserves the existing `ActivationMode.singleTap` and `ActivationMode.doubleTap` behavior in `DoubleTapDetector`.

- [ ] **Step 3: Keep old notification as a compatibility shim**

In `observeCiderPanelNotifications()`, change the `.toggleCiderPanel` sink to:

```swift
NotificationCenter.default.publisher(for: .toggleCiderPanel)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.performCiderActivation()
    }
    .store(in: &cancellables)
```

Do not call `showCiderPanel()` from `.toggleNoteEditor`; route it to `transitionToCiderMainWindow()` or a note-specific creation path if the hotkey creates notes.

- [ ] **Step 4: Manual verification**

Run:

```bash
swift test --filter CiderSurfaceRecallCoordinatorTests
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
```

Expected: tests and build pass.

Manual QA:
- Double tap Option opens main window when no floating work panel was used.
- Pop out a note, close it, double tap Option restores that note panel.
- Double tap Option again while that note panel is visible hides it.
- Switch Settings from double tap to single tap. A quick single Option tap performs the same Smart Recall.
- Holding Option, or using Option with another key, does not activate Cider.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/App/AppDelegate.swift Sources/Cider/App/AppDelegate+CiderPanel.swift
git commit -m "Route Option activation through smart recall"
```

---

### Task 4: Add Reanchor Notifications And Floating Panel Button

**Files:**
- Modify: `Sources/Cider/Utilities/Constants.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
- Modify: `Sources/Cider/App/AppDelegate.swift`

- [ ] **Step 1: Add notification names**

Add:

```swift
static let reanchorCiderSurface = Notification.Name("cider.reanchorCiderSurface")
static let openCiderSurfaceInMainWindow = Notification.Name("cider.openCiderSurfaceInMainWindow")
```

- [ ] **Step 2: Add reanchor posting helper**

Add near the existing `dock` helper in `CiderFloatingItemViews.swift`:

```swift
private func reanchor(_ surface: CiderFloatableSurface) {
    NotificationCenter.default.post(
        name: .reanchorCiderSurface,
        object: surface,
        userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
    )
}
```

- [ ] **Step 3: Add a visible button to each floating item header**

Where each floating item passes `trailingExtra` or header actions into `GenericItemDetailPanel`, add a plain icon button:

```swift
Button {
    reanchor(surface)
} label: {
    Image(systemName: "rectangle.arrowtriangle.2.inward")
        .font(CiderFont.bodySemibold)
}
.buttonStyle(.plain)
.help("Show in Cider")
```

Keep the current close/dock button. Reanchor should not close the panel in the first version.

- [ ] **Step 4: AppDelegate observes reanchor requests**

Add observer:

```swift
NotificationCenter.default.publisher(for: .reanchorCiderSurface)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        guard let self,
              let surface = CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: notification) else {
            return
        }
        self.transitionToCiderMainWindow()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openCiderSurfaceInMainWindow,
                object: surface,
                userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
            )
        }
    }
    .store(in: &cancellables)
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Utilities/Constants.swift Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift Sources/Cider/Views/Floating/CiderFloatingItemViews.swift Sources/Cider/App/AppDelegate.swift
git commit -m "Add reanchor action to floating panels"
```

---

### Task 5: Open Reanchored Surfaces In The Main Window

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Test: `Tests/CiderTests/CiderFloatableSurfaceTests.swift`

- [ ] **Step 1: Add pure resolver tests**

Add:

```swift
@Test("reanchor resolver accepts item surfaces")
func reanchorResolverAcceptsItemSurfaces() {
    #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.note(UUID())))
    #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.bookmarkMetadata(UUID())))
    #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.contact(UUID())))
    #expect(CiderReanchorSurfaceResolver.canOpenInMainWindow(.todo(UUID())))
}

@Test("reanchor resolver rejects utility surfaces")
func reanchorResolverRejectsUtilitySurfaces() {
    #expect(!CiderReanchorSurfaceResolver.canOpenInMainWindow(.dropZone))
    #expect(!CiderReanchorSurfaceResolver.canOpenInMainWindow(.clipboard))
    #expect(!CiderReanchorSurfaceResolver.canOpenInMainWindow(.aiAssistant))
}
```

- [ ] **Step 2: Add resolver**

Add to `CiderPanelView+DetailManagement.swift`:

```swift
enum CiderReanchorSurfaceResolver {
    static func canOpenInMainWindow(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo:
            true
        case .clipboard, .aiAssistant, .dropZone:
            false
        }
    }
}
```

- [ ] **Step 3: Observe main-window open requests**

In `CiderPanelView.body`, add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openCiderSurfaceInMainWindow)) { notification in
    guard surface == .mainWindow,
          let floatableSurface = CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: notification) else {
        return
    }
    openSurfaceInMainWindow(floatableSurface)
}
```

- [ ] **Step 4: Resolve surfaces to existing open methods**

Add:

```swift
func openSurfaceInMainWindow(_ surface: CiderFloatableSurface) {
    guard CiderReanchorSurfaceResolver.canOpenInMainWindow(surface) else { return }
    closeAllDetails()

    switch surface {
    case .note(let id):
        if let note = notesViewModel.notes.first(where: { $0.id == id }) {
            openNoteDetail(note)
        }
    case .bookmark(let id), .bookmarkMetadata(let id):
        if let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == id }) {
            openBookmarkDetails(bookmark)
        }
    case .contact(let id):
        if let contact = ContactCardStorage.shared.contacts.first(where: { $0.id == id }) {
            openContactDetail(contact)
        }
    case .dateCard(let id):
        if let dateCard = DateCardStorage.shared.dateCards.first(where: { $0.id == id }) {
            openDateCardDetail(dateCard)
        }
    case .todo(let id):
        if let todo = TodoCardStorage.shared.todoCards.first(where: { $0.id == id }) {
            openTodoDetail(todo)
        }
    case .clipboard, .aiAssistant, .dropZone:
        break
    }
}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
swift test --filter CiderFloatableSurfaceTests/reanchor
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
```

Expected: tests and build pass.

Manual QA:
- Pop out a note, click Show in Cider, main window focuses and opens that note.
- Repeat for bookmark metadata, contact, todo.
- Floating panel stays open.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/CiderPanelView.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Tests/CiderTests/CiderFloatableSurfaceTests.swift
git commit -m "Open reanchored surfaces in the main window"
```

---

### Task 6: Remove Old Quick Panel User Entry Points

**Files:**
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+TitleBar.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+KeyboardNavigation.swift`
- Modify: `Sources/Cider/Views/Shared/ClipboardPanelView.swift`
- Modify: `Sources/Cider/Services/SpotlightIndexer.swift`
- Modify: `Sources/Cider/Views/Settings/SettingsComponents.swift`
- Modify: `Sources/Cider/Views/Onboarding/OnboardingTabView.swift`

- [ ] **Step 1: Remove menu items**

In `installCiderApplicationMenuItems()` remove:

```swift
ciderMenu.addItem(statusMenuItem(title: "Show Quick Panel", action: #selector(showCiderPanelFromMenu), keyEquivalent: "2"))
```

In `configureStatusItem()` remove:

```swift
menu.addItem(statusMenuItem(title: "Show Quick Panel", action: #selector(showCiderPanelFromMenu), keyEquivalent: " "))
```

- [ ] **Step 2: Remove main-window toggle button for old panel**

In `normalTitleBar`, replace the surface-switching button with nothing for `.mainWindow`. If a future button is needed, make it "New floating surface" rather than "Show floating panel".

- [ ] **Step 3: Redirect old quick-panel notifications**

Replace posts to `.toggleCiderPanel` used for normal opening with `.openCiderMainWindow`.

Examples:

```swift
NotificationCenter.default.post(name: .openCiderMainWindow, object: nil)
```

Do this in:
- `SpotlightIndexer.swift`
- `ClipboardPanelView.swift`
- file-open handling in `AppDelegate.swift`

- [ ] **Step 4: Update copy**

Change settings shortcut text:

```swift
ShortcutEntry(keys: "Option \u{2325} double-tap", description: "Recall last Cider surface")
```

Change onboarding copy from "summon Cider" as a panel to "open Cider or recall your last floating panel".

- [ ] **Step 5: Search for remaining user-facing quick panel text**

Run:

```bash
rg "Quick Panel|quick panel|Toggle Cider panel|toggle Cider panel|Show floating panel|toggleCiderPanel" Sources/Cider Tests
```

Expected:
- No user-facing "Quick Panel" text remains.
- `toggleCiderPanel` may remain only as a deprecated compatibility notification or internal shim.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/Cider/App/AppDelegate.swift Sources/Cider/Views/CiderPanelView+TitleBar.swift Sources/Cider/Views/CiderPanelView+KeyboardNavigation.swift Sources/Cider/Views/Shared/ClipboardPanelView.swift Sources/Cider/Services/SpotlightIndexer.swift Sources/Cider/Views/Settings/SettingsComponents.swift Sources/Cider/Views/Onboarding/OnboardingTabView.swift
git commit -m "Remove old quick panel entry points"
```

---

### Task 7: Stop Creating The Old Full-App NSPanel

**Files:**
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/App/AppDelegate+CiderPanel.swift`
- Modify: `Sources/Cider/App/CiderSurfaceTransitionPolicy.swift`
- Test: `Tests/CiderTests/CiderSurfaceTransitionPolicyTests.swift`

- [ ] **Step 1: Rewrite transition tests**

Replace quick-panel transition tests with:

```swift
@Test("launching Cider starts as a regular app with the main window visible")
func launchTransitionShowsMainWindow() {
    let transition = CiderSurfaceTransitionPolicy.launchTransition()

    #expect(transition.activationPolicy == .regular)
    #expect(transition.shouldShowMainWindow)
    #expect(!transition.shouldHideMainWindow)
    #expect(transition.shouldActivateApp)
}

@Test("opening the main window uses regular app activation")
func mainWindowTransitionUsesRegularAppActivation() {
    let transition = CiderSurfaceTransitionPolicy.transitionToMainWindow()

    #expect(transition.activationPolicy == .regular)
    #expect(transition.shouldShowMainWindow)
    #expect(!transition.shouldHideMainWindow)
    #expect(transition.shouldActivateApp)
}
```

- [ ] **Step 2: Simplify transition policy**

Change `CiderSurfaceTransitionPolicy` to expose only:

```swift
enum CiderWorkspaceSurface {
    case mainWindow
}

struct CiderSurfaceTransition {
    let activationPolicy: NSApplication.ActivationPolicy
    let shouldShowMainWindow: Bool
    let shouldHideMainWindow: Bool
    let shouldActivateApp: Bool
}

enum CiderSurfaceTransitionPolicy {
    static func launchTransition() -> CiderSurfaceTransition {
        transitionToMainWindow()
    }

    static func transitionToMainWindow() -> CiderSurfaceTransition {
        CiderSurfaceTransition(
            activationPolicy: .regular,
            shouldShowMainWindow: true,
            shouldHideMainWindow: false,
            shouldActivateApp: true
        )
    }
}
```

- [ ] **Step 3: Stop configuring the old panel**

In `applicationDidFinishLaunching`, remove:

```swift
configureCiderPanel()
observeCiderPanelNotifications()
```

Replace `observeCiderPanelNotifications()` with a small `observeActivationNotifications()` if needed.

- [ ] **Step 4: Remove old panel fields when no references remain**

Remove from `AppDelegate`:

```swift
var ciderPanel: CiderPanel?
var ciderShadowPanel: CiderShadowPanel?
var panelFrameObservation: NSKeyValueObservation?
let ciderPanelPositionStore = CiderPanelPositionStore.shared
var frameBeforeSlideOut: NSRect?
```

Keep `CiderShadowPanel` if clipboard/assistant still use it.

- [ ] **Step 5: Delete or shrink old panel implementation**

If `rg "CiderPanel\\b|showCiderPanel|hideCiderPanel|transitionToQuickPanel|quickPanel" Sources/Cider Tests` shows no runtime references, delete:

```bash
git rm Sources/Cider/App/CiderPanel.swift Sources/Cider/App/AppDelegate+CiderPanel.swift
```

If there are still compatibility references, leave `AppDelegate+CiderPanel.swift` as a short deprecated shim:

```swift
extension AppDelegate {
    func toggleCiderPanel() {
        performCiderActivation()
    }

    func showCiderPanel() {
        transitionToCiderMainWindow()
    }

    func hideCiderPanel() {
        hideCiderMainWindow()
    }
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift test
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
```

Expected: all tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Cider/App AppDelegate.swift Sources/Cider/App/CiderSurfaceTransitionPolicy.swift Tests/CiderTests/CiderSurfaceTransitionPolicyTests.swift
git add -u Sources/Cider/App
git commit -m "Deprecate old full app panel runtime"
```

---

### Task 8: End-To-End QA And Final Commit

**Files:**
- No required file ownership unless QA finds issues.

- [ ] **Step 1: Relaunch app**

Run:

```bash
osascript -e 'tell application "Cider" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Cider >/dev/null 2>&1 || true
open /Users/minivish/Cider/.deriveddata/Build/Products/Debug/Cider.app
```

- [ ] **Step 2: QA main app**

Manual checks:
- Launch opens normal main window.
- Relaunch restores/reopens normal main window.
- Menu bar icon has no "Show Quick Panel".
- Main window drag zones still work.
- Tab reordering still works.
- Dashboard, Inbox, Library resize still work.
- Masonry/grid/list switching still works.

- [ ] **Step 3: QA Smart Recall**

Manual checks:
- With no prior floating work panel, Option activation opens main window.
- Pop out note, close it, Option activation restores note panel.
- Option activation while restored note panel is visible hides it.
- Repeat for bookmark metadata, contact, todo.
- Drop zone does not become last recalled surface.
- Clipboard and AI Assistant do not become last recalled surface unless we intentionally add them later.
- Single quick tap mode still works.
- Holding Option does not activate Cider.
- Option plus another key does not activate Cider.

- [ ] **Step 4: QA reanchor**

Manual checks:
- Floating note "Show in Cider" opens main window to that note.
- Floating bookmark metadata "Show in Cider" opens main window to that bookmark detail.
- Floating contact "Show in Cider" opens main window to that contact.
- Floating todo "Show in Cider" opens main window to that todo.
- Floating panel remains open after reanchor.

- [ ] **Step 5: Final verification**

Run:

```bash
swift test
xcodebuild -project Cider.xcodeproj -scheme CiderApp -configuration Debug -derivedDataPath .deriveddata build
git status --short
```

Expected:
- Tests pass.
- Build succeeds.
- Dirty files only include intentional Cider source/test changes plus pre-existing unrelated user files.

- [ ] **Step 6: Commit final QA fixes**

```bash
git add Sources/Cider Tests/CiderTests
git commit -m "Finalize smart recall panel deprecation"
```

---

## Self-Review

- Spec coverage: The plan covers old full-app NSPanel deprecation, Option single/double tap preservation, Smart Recall, reanchor button, menu/settings/onboarding copy, tests, build, and manual QA.
- Placeholder scan: No `TBD` or deferred implementation placeholders remain. Steps that depend on `rg` results give exact fallback code.
- Type consistency: `CiderSurfaceRecallCoordinator`, `CiderSurfaceActivationAction`, and notification names are defined before use. `CiderFloatableSurface` is the common payload type throughout.
- Scope check: This is one architecture cleanup with three parallel lanes. The only shared integration hotspot is `AppDelegate`, called out for the integrator.
