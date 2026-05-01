# Cider Main Brain AI Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Cider open one stable Hermes-backed Main Brain chat by default, and make the AI chat a normal Cider surface that can live in the main window or float like other surfaces.

**Architecture:** Cider gets a small app-level registry record for `cider.main`, which maps the stable Cider chat identity to the current Hermes runtime session and lineage. The AI UI keeps using `AIAssistantPanelView`, but `.aiAssistant` becomes a regular `CiderFloatableSurface` handled by `CiderFloatingPanelManager` and recallable by double-tap Option.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, local JSON storage, existing Hermes CLI/state.db adapter.

---

### Task 1: Persist The Main Brain Mapping

**Files:**
- Create: `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`
- Test: `Tests/CiderTests/CiderAgentChatRegistryTests.swift`

- [ ] Add `CiderAgentChatRecord` with stable ID, title, runtime ID, conversation UUID, active Hermes session ID, lineage, timestamps, and `defaultInCider`.
- [ ] Add `CiderAgentChatRegistry` with an injectable storage URL, `loadOrCreateMainBrain()`, and `saveMainBrain(_:)`.
- [ ] Seed `cider.main` from the current Hermes lineage:
  - `20260501_045533_cce0d1c1`
  - `20260501_100416_ebff7f`
  - `20260501_114444_443f9e`
  - `20260501_120144_e3d994`
- [ ] Write tests proving first load creates the seed record and later loads preserve the same conversation UUID.

### Task 2: Route Hermes Mode Through Main Brain

**Files:**
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Test: existing Hermes tests plus compile verification.

- [ ] Add a registry dependency to `AIAssistantViewModel`.
- [ ] Update `activateHermesConversation()` so Hermes mode opens `cider.main` instead of the most recent arbitrary Hermes conversation.
- [ ] Update Hermes sync/send completion to save the latest active runtime session and lineage back into the registry.
- [ ] Keep non-Hermes conversation history behavior unchanged.

### Task 3: Make AI A Normal Floatable Surface

**Files:**
- Modify: `Sources/Cider/App/CiderFloatingPanelManager.swift`
- Modify: `Sources/Cider/App/CiderSurfaceRecallCoordinator.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
- Modify: `Sources/Cider/App/AppDelegate+AIAssistantPanel.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`
- Test: `Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift`

- [ ] Let `.aiAssistant` pass through `CiderFloatingPanelManager.handleFloatSurfaceNotification(_:)`.
- [ ] Make `.aiAssistant` recallable and restorable.
- [ ] Render `AIAssistantPanelView(viewModel:onClose:)` for `.aiAssistant` inside `CiderFloatingSurfaceView`.
- [ ] Route legacy `.showAIAssistantPanel`, `.toggleAIAssistantPanel`, and `.dismissAIAssistantPanel` notifications to the floating panel manager.
- [ ] Update sidebar AI actions to post the enum surface payload instead of a string.

### Task 4: Add Main-Window AI Chat Surface

**Files:**
- Modify: `Sources/Cider/Models/CiderTab.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+TabManagement.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+ContentArea.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Modify: `Sources/Cider/Views/Shared/CiderTabBar.swift`

- [ ] Add `CiderTab.aiAssistant`.
- [ ] Add `openOrSelectAIAssistantTab()` and use it from the sidebar's primary AI button.
- [ ] Render the same AI chat view in the main content area for the AI tab.
- [ ] Allow `.aiAssistant` to reanchor into the main window from a floating surface.
- [ ] Keep “Open Chat” in quick actions as an explicit floating action if needed.

### Task 5: Verify

**Files:**
- Test command target only.

- [ ] Run `swift test --filter CiderAgentChatRegistryTests`.
- [ ] Run `swift test --filter CiderSurfaceRecallCoordinatorTests`.
- [ ] Run `swift test`.
- [ ] Run `xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build`.
