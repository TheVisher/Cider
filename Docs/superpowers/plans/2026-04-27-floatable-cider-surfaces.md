# Floatable Cider Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the normal Cider window the primary full app surface while adding a reusable NSPanel system for floating notes, bookmarks, contacts, date cards, todos, AI, clipboard, and a first drop zone prototype.

**Architecture:** Keep Cider as one app with shared services/view models. Add a central floatable-surface model and panel manager, then have feature views request floating panels through notifications instead of creating one-off panels. Preserve the existing quick panel as a summonable surface while the main window becomes the default home base.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSWindow`/`NSPanel`, existing Cider services and view models, Swift Testing/XCTest.

---

### Task 1: Floatable Surface Core

**Files:**
- Create: `Sources/Cider/App/CiderFloatableSurface.swift`
- Create: `Sources/Cider/App/CiderFloatingPanel.swift`
- Create: `Sources/Cider/App/CiderFloatingPanelManager.swift`
- Create: `Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift`
- Modify: `Sources/Cider/Utilities/Constants.swift`
- Test: `Tests/CiderTests/CiderFloatableSurfaceTests.swift`

- [ ] Add a `CiderFloatableSurface` enum covering `note`, `bookmark`, `bookmarkMetadata`, `contact`, `dateCard`, `todo`, `clipboard`, `aiAssistant`, and `dropZone`.
- [ ] Add notification names: `.floatCiderSurface`, `.dockCiderSurface`, `.showCiderDropZone`.
- [ ] Add `CiderFloatingPanel`, a reusable borderless non-activating floating panel with drag support and standard sizing.
- [ ] Add `CiderFloatingPanelManager` that reuses an existing panel for the same surface, creates panels through `CiderFloatingSurfaceView`, closes panels, and can show panels near the mouse.
- [ ] Add tests for stable identity/title defaults and manager keying behavior that does not require opening real windows.

### Task 2: Main Window And Quick Panel Roles

**Files:**
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/App/AppDelegate+CiderMainWindow.swift`
- Modify: `Sources/Cider/App/AppDelegate+CiderPanel.swift`
- Modify: `Sources/Cider/App/CiderMainWindow.swift`
- Modify: `Sources/Cider/App/CiderSurfaceTransitionPolicy.swift`
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/Shared/CiderPanelShell.swift`
- Test: `Tests/CiderTests/CiderSurfaceTransitionPolicyTests.swift`

- [ ] Keep app activation policy `.regular`.
- [ ] Show `CiderMainWindow` at launch as the primary full Cider workspace.
- [ ] Keep the old full Cider panel as the quick floating panel invoked by hotkey/menu.
- [ ] Make the main window chrome use native window controls while the quick panel keeps custom panel controls.
- [ ] Add menu items for showing the main window, quick panel, AI panel, clipboard panel, and drop zone.
- [ ] Ensure transition policy tests cover main-window launch, quick-panel summon, and panel-to-window handoff.

### Task 3: Float Notes And Library Items

**Files:**
- Create: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+TitleBar.swift`
- Modify: `Sources/Cider/Views/Shared/GenericItemDetailPanel.swift`
- Modify: `Sources/Cider/Views/Shared/DetailSlideOutView.swift`

- [ ] Add reusable float buttons to detail title/header areas where practical.
- [ ] Let notes, bookmark metadata/details, contacts, date cards, and todos request `.floatCiderSurface` with their item IDs.
- [ ] Render each floated item with the existing detail/editor view where feasible; use a simple fallback view when an existing detail view cannot be safely reused in isolation.
- [ ] Avoid duplicate active note editing conflicts by making the floating note view either reuse the existing note editor model safely or display a read-first fallback if reuse is too risky for the one-shot prototype.

### Task 4: Migrate Existing Special Panels Into The Model

**Files:**
- Modify: `Sources/Cider/App/AppDelegate+AIAssistantPanel.swift`
- Modify: `Sources/Cider/App/AppDelegate+ClipboardPanel.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+TitleBar.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`

- [ ] Keep existing `AIAssistantPanel` and `ClipboardPanel` behavior intact.
- [ ] Add compatibility so `.floatCiderSurface` with `.aiAssistant` opens the existing AI panel.
- [ ] Add compatibility so `.floatCiderSurface` with `.clipboard` opens the existing clipboard panel.
- [ ] Route titlebar/sidebar buttons through the floatable-surface API where this does not break current hotkeys.

### Task 5: Floating Drop Zone Prototype

**Files:**
- Create: `Sources/Cider/App/CiderDropZoneContext.swift`
- Create: `Sources/Cider/Views/Floating/CiderDropZoneView.swift`
- Modify: `Sources/Cider/App/CiderFloatingPanelManager.swift`
- Modify: `Sources/Cider/App/AppDelegate.swift`
- Modify: `Sources/Cider/Utilities/Constants.swift`

- [ ] Add a small floating drop zone surface.
- [ ] Accept file URLs, web URLs, plain text, and images through SwiftUI drop handling.
- [ ] Route dropped URLs to bookmark capture where possible.
- [ ] Route dropped files/images into the vault inbox using existing storage helpers where practical; otherwise show a clear prototype fallback state.
- [ ] Add a menu item to show the drop zone for testing.

### Task 6: Verification And Integration

**Files:**
- Modify as needed based on compile errors only.

- [ ] Run `swift test --filter CiderSurfaceTransitionPolicyTests`.
- [ ] Run `swift test --filter CiderFloatableSurfaceTests`.
- [ ] Run `xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug build`.
- [ ] Fix compile errors without broad unrelated refactors.
- [ ] Record known limitations for manual testing.

## Future Direction: Clipboard Inbox

- Treat clipboard history as Cider's passive ingestion inbox: copied URLs, text, images, and files accumulate while the user works normally.
- Add "Save to Cider" actions on clipboard items so an old copied item can become a bookmark, note, image/file capture, contact, or other future entity without needing to re-find it.
- Connect this with the floating Drop Zone model: clipboard is the reviewable backlog, Drop Zone is the active drag target, and floatable panels are the lightweight triage/edit surfaces.
- Preserve history long enough that content copied days or weeks ago can still be promoted into Cider later.

## Future Direction: Desktop-Pinned Surfaces

- After the main desktop app shell is solid, add a third presence mode for floatable surfaces: desktop pinned.
- Keep the modes distinct: main app is the full workspace, floating panel stays above other apps for quick action/reference, and desktop pin behaves like an interactive sticky note/widget that lives on the desktop.
- Model this as panel presence on `CiderFloatingPanel`, not a separate content system, so notes, todos, bookmarks, contact cards, and future surfaces can opt into it consistently.
- Useful cases include todo reminders pinned until handled, notes as scratchpads, bookmarks/references while working, contact cards during calls, and lightweight desktop organization/content curation.
- Explore `NSWindow.Level` and `collectionBehavior` combinations for desktop behavior while keeping panels interactable.
