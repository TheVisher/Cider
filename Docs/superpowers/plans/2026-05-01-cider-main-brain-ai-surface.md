# Cider Main Brain AI Surface Implementation Plan

> Status: historical handoff/checkpoint. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`.

> **For agentic workers:** This plan is now mostly implemented. Use it as historical implementation context, not as the next work queue. The follow-up hardening plan is `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`.

**Goal:** Make Cider open one stable Hermes-backed Main Brain chat by default, and make the AI chat a normal Cider surface that can live in the main window or float like other surfaces.

**Architecture:** Cider owns a stable logical chat record, `cider.main`, while Hermes owns the runtime session, compaction, tools, and agent memory. `CiderAgentChatRegistry` maps the stable Cider chat identity to the current Hermes session and lineage. `AIAssistantPanelView` is now reused in the main content area and floating surface system.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, local JSON storage, existing Hermes CLI/state.db adapter.

**Status:** `Shipped / Needs Sign-off`

**Updated:** 2026-05-02

---

## Current Implementation Notes

- `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift` persists the stable `cider.main` record under `.cider/agent-chats/cider.main.json`.
- `Sources/Cider/Services/Agent/HermesSessionClient.swift` reads Hermes session continuity from `~/.hermes/state.db`, exports transcripts through `hermes sessions export`, sends through `hermes chat --resume`, and polls live session files for in-progress response updates.
- `Sources/Cider/ViewModels/AIAssistantViewModel.swift` activates the Main Brain when Hermes mode is selected, syncs the Hermes transcript into Cider conversation storage, persists the latest active Hermes runtime session, and keeps the UI updated while a send is in progress.
- `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift` renders the Main Brain surface and sync controls.
- `.aiAssistant` is a normal Cider tab/floatable surface through `CiderTab`, `CiderPanelView+ContentArea`, `CiderFloatingSurfaceView`, `CiderFloatingPanelManager`, and `CiderSurfaceRecallCoordinator`.
- The old dedicated `AIAssistantPanel` object still exists as a compatibility shell, but legacy show/toggle/dismiss notifications now route through the floating surface manager.

## Important Product Clarification

The current implementation is a strong v0 of **Cider as a Hermes session client**, not a true shared multi-client room yet.

**Hardening follow-up:** The seeded local Hermes lineage from this plan has been replaced by the explicit attach/create/repair flow in `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`. Treat the seed IDs here as historical implementation context only.

Cider can:

- attach to the stable Main Brain mapping
- resume the active Hermes session
- import/sync Telegram-origin Hermes messages
- show live-ish response progress by polling Hermes session files
- persist a local Cider mirror of the visible conversation

Cider does not yet:

- own a host-level event stream shared by Telegram, Cider, mobile, and CLI
- guarantee cross-client send locking if Telegram and Cider both send at the same time
- broadcast Cider-origin turns back into Telegram unless Hermes/Telegram handles that path
- provide a user-facing attach/relink flow for non-Erik installs

Those are follow-up hardening/productization items, not failures of this plan.

---

## Task Status

### Task 1: Persist The Main Brain Mapping

**Files:**
- Created: `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`
- Test: `Tests/CiderTests/CiderAgentChatRegistryTests.swift`

- [x] Add `CiderAgentChatRecord` with stable ID, title, runtime ID, conversation UUID, active Hermes session ID, lineage, timestamps, and `defaultInCider`.
- [x] Add `CiderAgentChatRegistry` with an injectable storage URL and `saveMainBrain(_:)`.
- [x] Superseded by the 2026-05-02 hardening pass: `cider.main` is no longer seeded from a developer-specific Hermes lineage. Fresh installs remain unattached until the user explicitly attaches latest Telegram, chooses an existing Hermes session, or starts a fresh Hermes session.
- [x] Write tests proving an empty registry does not create a seed record, explicit create persists caller-supplied Hermes state, and later loads preserve the same conversation UUID.

**Follow-up resolved by hardening pass:** The hard-coded seed lineage was removed before this ships to other users.

### Task 2: Route Hermes Mode Through Main Brain

**Files:**
- Modified: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Test: existing Hermes tests plus compile verification.

- [x] Add a registry dependency to `AIAssistantViewModel`.
- [x] Update `activateHermesConversation()` so Hermes mode opens `cider.main` instead of the most recent arbitrary Hermes conversation.
- [x] Update Hermes sync/send completion to save the latest active runtime session and lineage back into the registry.
- [x] Keep non-Hermes conversation history behavior unchanged.

**Follow-up:** Add a visible attach/relink/repair path for when the stored Hermes session disappears, forks unexpectedly, or belongs to a different source than the user expects.

### Task 3: Make AI A Normal Floatable Surface

**Files:**
- Modified: `Sources/Cider/App/CiderFloatingPanelManager.swift`
- Modified: `Sources/Cider/App/CiderSurfaceRecallCoordinator.swift`
- Modified: `Sources/Cider/Views/Floating/CiderFloatingSurfaceView.swift`
- Modified: `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
- Modified: `Sources/Cider/App/AppDelegate+AIAssistantPanel.swift`
- Modified: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`
- Test: `Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift`

- [x] Let `.aiAssistant` pass through `CiderFloatingPanelManager.handleFloatSurfaceNotification(_:)`.
- [x] Make `.aiAssistant` recallable and restorable.
- [x] Render `AIAssistantPanelView(viewModel:onClose:)` for `.aiAssistant` inside `CiderFloatingSurfaceView`.
- [x] Route legacy `.showAIAssistantPanel`, `.toggleAIAssistantPanel`, and `.dismissAIAssistantPanel` notifications to the floating panel manager.
- [x] Update sidebar AI actions to open/select the AI tab and retain an explicit floating action.

### Task 4: Add Main-Window AI Chat Surface

**Files:**
- Modified: `Sources/Cider/Models/CiderTab.swift`
- Modified: `Sources/Cider/Views/CiderPanelView+TabManagement.swift`
- Modified: `Sources/Cider/Views/CiderPanelView+ContentArea.swift`
- Modified: `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`
- Modified: `Sources/Cider/Views/Shared/CiderTabBar.swift`

- [x] Add `CiderTab.aiAssistant`.
- [x] Add `openOrSelectAIAssistantTab()` and use it from the sidebar's primary AI button.
- [x] Render the same AI chat view in the main content area for the AI tab.
- [x] Allow `.aiAssistant` to reanchor into the main window from a floating surface.
- [x] Keep quick actions able to open the AI panel flow.

### Task 5: Verify

**Current verification from 2026-05-02:**

- [x] Run `swift test --filter HermesSessionClientTests`.
  - Result: passed, 5 tests.
- [x] Run `swift test --filter CiderAgentChatRegistryTests`.
  - Result: passed, 3 tests.
- [ ] Run `swift test --filter CiderSurfaceRecallCoordinatorTests`.
- [ ] Run `swift test`.
- [ ] Run `xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build`.

## Known Hardening Queue

These belong in the follow-up plan:

- Add a first-run attach/create/relink flow instead of relying on developer seed Hermes session IDs.
- Add stronger dedupe between live session-file messages and final Hermes export messages.
- Add send/run coordination so Cider does not send into a busy Hermes session blindly.
- Keep all direct Hermes internals behind `HermesSessionClient.swift`.
- Decide how much Cider should mirror Hermes transcripts versus treating Hermes as the durable source of truth.
