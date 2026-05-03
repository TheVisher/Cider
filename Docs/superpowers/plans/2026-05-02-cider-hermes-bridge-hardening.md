# Cider Hermes Bridge Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Cider's Main Brain chat feel like Hermes inside Cider: stable named brain, native command surface, clear run state, streaming when available, and repairable Hermes continuity.

**Architecture:** Hermes remains the runtime and source of truth for agent execution, session continuity, tools, memory, compaction, approvals, execution semantics for forwarded slash commands, and run state. Cider owns stable chat identity, native UI, local mirrored display history, search/offline affordances, attach/relink/repair controls, slash-command parsing/routing/presentation, and vault actions. Keep all direct Hermes details behind small client types in `Sources/Cider/Services/Agent/`; the existing CLI/export/session-file bridge remains a fallback while the preferred transport becomes Hermes API server Runs/SSE when capabilities prove available.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, URLSession, local JSON/JSONL storage, Hermes CLI, Hermes API server on `127.0.0.1:8642`, Server-Sent Events, Hermes `state.db`, Hermes `sessions export`.

---

## Current State

Cider already has a usable Main Brain v0:

- `CiderAgentChatRegistry` persists stable chat ID `cider.main`.
- `AIAssistantViewModel` opens the Main Brain when Hermes mode is selected.
- `HermesSessionService` follows Hermes continuation lineage through `~/.hermes/state.db`.
- The current send path uses `hermes chat --resume`, final transcript sync uses `hermes sessions export`, and in-progress display polls `~/.hermes/sessions/session_<id>.json`.
- The AI panel can live in the main window or float like other Cider surfaces.
- Telegram-origin Hermes messages appear in Cider after sync.
- The live/export dedupe fix is already implemented in `HermesTranscriptMerger` and covered by `HermesSessionClientTests`.
- Hermes session titles are global enough for cross-client recall: Cider-created sessions can be resumed from Telegram by explicit `/resume <Hermes session title>` if Cider writes the friendly name into Hermes as the actual session title.
- Cider-created named chats work from Telegram by explicit `/resume <title>`, which is enough for remote access for now.
- Durable sync cursors and title-based stale-session repair are implemented.

## Direction Pivot, 2026-05-02

The current product target is **Cider Main Brain Chat parity with Hermes**, not perfect Cider to Telegram transcript sync.

The primary Cider chat is:

- logical chat ID: `cider.main`
- display name: `Cider`
- Hermes visible title: `Cider`
- human aliases: Cider, Main Brain, Vault, Brain
- safety rule: v1 `/title` must not casually rename `cider.main` away from the canonical Hermes title `Cider`
- safety rule: v1 `/new` must not silently strand the canonical brain; require confirmation or create a clearly separate fresh chat while preserving the existing record/lineage

Telegram or Discord should be treated as remote access surfaces that can resume the named Cider brain with `/resume Cider`. They do not need to visually mirror Cider's full transcript, and Cider does not need to import every external message perfectly before the native Cider chat can improve.

The next implementation slice is the **Cider-native slash command router**. This gives Cider an immediate Hermes-like command surface without waiting for the Hermes API server to be reachable.

## Product Bar

Cider chat should eventually feel like a real Hermes client, not a nicer file watcher:

- no developer-specific seeded Hermes session IDs,
- explicit unattached, attached, stale, running, waiting, and error states,
- visible attach, relink, repair, and start-fresh controls,
- Cider-origin turns serialized enough to avoid local double-sends,
- Hermes-origin runtime state preferred over guessed local state,
- streaming or near-live response display,
- structured tool progress separate from final assistant text,
- native stop/cancel when Hermes supports it,
- native approval UI when Hermes exposes a supported approval event/response path,
- named side chats so scoped work can avoid flooding Main Brain while still being resumable from Telegram,
- local mirrored transcript for UI/search/offline use without competing with Hermes runtime history.
- native slash commands such as `/help`, `/status`, `/resume`, `/last`, `/summary`, `/checkpoint`, `/new`, and `/title`.
- composer command discovery so typing `/` reveals available Cider commands and filters them as the draft changes.

## Discovered Hermes Contract

Local Hermes `v0.12.0 (2026.4.30)` documents a supported API server behind the gateway:

- `GET /v1/capabilities`
- `POST /v1/runs`
- `GET /v1/runs/{run_id}`
- `GET /v1/runs/{run_id}/events`
- `POST /v1/runs/{run_id}/stop`
- `X-Hermes-Session-Id` for API-server session continuity on chat/responses endpoints
- SSE events including `message.delta`, `tool.started`, `tool.completed`, `reasoning.available`, `run.completed`, `run.failed`, and `run.cancelled`

The installed gateway is running, but the API server was not reachable at `127.0.0.1:8642` during discovery. The plan must therefore first add a capability probe and document the exact local enablement path, then wire API Runs behind a transport seam with CLI/export fallback.

This API work remains valuable, but the reason has changed. The Runs/SSE path is for making Cider chat stream and control Hermes natively, not for perfect Cider/Telegram synchronization.

## Non-Goals

- Do not replace Hermes with a Cider-owned agent runtime.
- Do not build unrelated AI features on the shaky bridge.
- Do not expose raw Hermes internals broadly through SwiftUI.
- Do not make file polling more central than it already is.
- Do not build a standalone multi-client room host in this phase.
- Do not optimize for perfect Telegram/Cider transcript mirroring.
- Do not build Cody, Mac, Nexus, Discord-first routing, or a multi-agent roster before the Cider second-brain chat feels excellent.
- Do not create new architecture docs for speculative agent ideas; update this plan and the adaptive roadmap unless Erik asks for a new doc.

---

## File Structure

- `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`
  Owns stable Hermes chat registry persistence. Remove seeded Hermes IDs, keep `cider.main` as the default record, and add named side-chat create/load/update/archive APIs.
- `Sources/Cider/Services/Agent/HermesSessionClient.swift`
  Keeps existing CLI/export/state.db fallback and transcript parsing. Add Hermes session rename support for named chats.
- `Sources/Cider/Services/Agent/HermesAPIClient.swift`
  New API-server client for health, capabilities, run creation, run polling, stop, and SSE event parsing.
- `Sources/Cider/Services/Agent/HermesBridgeTransport.swift`
  New transport protocol plus result/event types shared by CLI fallback and API Runs transport.
- `Sources/Cider/Services/Agent/HermesRunTransport.swift`
  New preferred transport using Hermes API Runs/SSE.
- `Sources/Cider/Services/Agent/CiderChatCommandRouter.swift`
  New lightweight command router for Cider-native slash commands. Handles local commands first and returns structured actions for commands that should resume, rename, summarize, checkpoint, or forward to Hermes.
- `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
  Owns Main Brain UI state, explicit attach/relink/start-fresh commands, send coordination, slash command execution, and transport selection.
- `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
  Adds compact attach/relink/repair controls and status rendering.
- `Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift`
  Disables send/stops correctly based on Hermes run state if the existing `isStreaming` boolean is not expressive enough. Also owns composer-level slash command discovery UI.
- `Tests/CiderTests/CiderAgentChatRegistryTests.swift`
  Covers no seeded session creation and create/update behavior.
- `Tests/CiderTests/HermesSessionClientTests.swift`
  Keeps existing CLI/export parser and dedupe coverage.
- `Tests/CiderTests/HermesAPIClientTests.swift`
  New tests for capabilities and SSE parsing with a fake URL protocol or pure parser helpers.
- `Tests/CiderTests/HermesBridgeTransportTests.swift`
  New tests for run event reduction and send-state transitions.
- `Docs/Architecture/AGENT_SERVICE.md`
  Documents Cider/Hermes ownership and the API Runs preferred transport.
- `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
  Keeps the roadmap aligned with the implemented order.

---

## Task 1: Remove Seeded Main Brain Bootstrap

**Purpose:** A fresh install must never inherit Erik-specific Hermes sessions.

**Files:**
- Modify: `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`
- Modify: `Tests/CiderTests/CiderAgentChatRegistryTests.swift`

- [ ] **Step 1: Replace the seeded-load test with an empty-load test**

Replace `firstLoadCreatesSeededMainBrainRecord()` in `Tests/CiderTests/CiderAgentChatRegistryTests.swift` with:

```swift
@Test("empty registry does not create seeded Hermes main brain")
func emptyRegistryDoesNotCreateSeededMainBrain() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
    let record = try registry.loadMainBrain()

    #expect(record == nil)
    #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("cider.main.json").path))
}
```

- [ ] **Step 2: Add an explicit create test**

Add this test to the same file:

```swift
@Test("create main brain persists caller supplied Hermes state")
func createMainBrainPersistsCallerSuppliedHermesState() throws {
    let tempDir = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
    let conversationID = UUID()
    let state = HermesConversationState(
        conversationID: conversationID,
        activeRuntimeSessionID: "fresh-session-2",
        runtimeSessionLineage: ["fresh-session-1", "fresh-session-2"],
        title: "Latest Telegram",
        source: "telegram",
        lastSyncedAt: Date(timeIntervalSince1970: 1_777_680_000)
    )

    let created = try registry.createMainBrain(from: state)
    let loaded = try registry.loadMainBrain()

    #expect(created.stableID == CiderAgentChatRegistry.mainBrainStableID)
    #expect(created.title == CiderAgentChatRegistry.mainBrainTitle)
    #expect(created.kind == CiderAgentChatRegistry.mainBrainKind)
    #expect(created.conversationID == conversationID)
    #expect(created.runtimeID == "hermes")
    #expect(created.activeRuntimeSessionID == "fresh-session-2")
    #expect(created.runtimeSessionLineage == ["fresh-session-1", "fresh-session-2"])
    #expect(created.defaultInCider)
    #expect(loaded == created)
}
```

- [ ] **Step 3: Run the registry tests and verify they fail**

Run:

```bash
swift test --filter CiderAgentChatRegistryTests
```

Expected: failure because `loadMainBrain()` and `createMainBrain(from:)` do not exist yet.

- [ ] **Step 4: Add explicit registry APIs and remove seeded creation**

In `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`, delete `seedHermesLineage` and replace `loadOrCreateMainBrain()` with:

```swift
func loadMainBrain() throws -> CiderAgentChatRecord? {
    lock.lock()
    defer { lock.unlock() }

    try ensureDirectory()
    let url = recordURL(for: Self.mainBrainStableID)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try decoder.decode(CiderAgentChatRecord.self, from: data)
}

func createMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
    let now = Date()
    let record = CiderAgentChatRecord(
        stableID: Self.mainBrainStableID,
        title: Self.mainBrainTitle,
        kind: Self.mainBrainKind,
        conversationID: state.conversationID,
        runtimeID: state.runtimeID,
        activeRuntimeSessionID: state.activeRuntimeSessionID,
        runtimeSessionLineage: state.runtimeSessionLineage,
        createdAt: now,
        updatedAt: now,
        defaultInCider: true
    )
    try saveMainBrain(record)
    return record
}
```

Update `updateMainBrain(from:)` so it creates from state when the record does not exist:

```swift
func updateMainBrain(from state: HermesConversationState) throws -> CiderAgentChatRecord {
    guard var record = try loadMainBrain() else {
        return try createMainBrain(from: state)
    }

    record.conversationID = state.conversationID
    record.runtimeID = state.runtimeID
    record.activeRuntimeSessionID = state.activeRuntimeSessionID
    record.runtimeSessionLineage = mergedLineage(record.runtimeSessionLineage, state.runtimeSessionLineage)
    record.title = Self.mainBrainTitle
    record.kind = Self.mainBrainKind
    record.defaultInCider = true
    record.updatedAt = Date()
    try saveMainBrain(record)
    return record
}
```

- [ ] **Step 5: Update existing registry tests to use explicit creation**

In `laterLoadsPreserveConversationIdentity()`, create the first record from a state:

```swift
let state = HermesConversationState(
    activeRuntimeSessionID: "session-a",
    runtimeSessionLineage: ["session-a"],
    title: "Main Brain",
    source: "telegram"
)
let first = try registry.createMainBrain(from: state)
let second = try registry.loadMainBrain()
```

In `hermesUpdatesMoveRuntimePointer()`, create the initial record from:

```swift
let first = try registry.createMainBrain(from: HermesConversationState(
    activeRuntimeSessionID: "20260501_120144_e3d994",
    runtimeSessionLineage: ["20260501_120144_e3d994"],
    title: "Cider Vault Agent #4",
    source: "telegram"
))
```

Change the expected lineage in that test to:

```swift
#expect(updated.runtimeSessionLineage == [
    "20260501_120144_e3d994",
    "20260501_130000_next"
])
```

- [ ] **Step 6: Run the registry tests**

Run:

```bash
swift test --filter CiderAgentChatRegistryTests
```

Expected: all registry tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift Tests/CiderTests/CiderAgentChatRegistryTests.swift
git commit -m "fix: remove seeded Hermes main brain sessions"
```

---

## Task 2: Add Explicit Unattached And Attach Flow

**Purpose:** Cider should show a clear setup/repair state when `cider.main` has no Hermes session.

**Files:**
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
- Test: `Tests/CiderTests/CiderAgentChatRegistryTests.swift`

- [ ] **Step 1: Extend panel status**

Replace `HermesPanelSyncStatus` in `Sources/Cider/ViewModels/AIAssistantViewModel.swift` with:

```swift
enum HermesPanelSyncStatus: Equatable {
    case notAttached
    case idle
    case syncing
    case sending
    case running(runID: String?)
    case waitingForApproval(String?)
    case staleSession(String)
    case disconnected(String)
    case error(String)
}
```

- [ ] **Step 2: Update status title mapping**

Update `hermesStatusTitle` with:

```swift
var hermesStatusTitle: String {
    switch hermesSyncStatus {
    case .notAttached:
        return "Attach Hermes"
    case .idle:
        guard runtimeSelection == .hermes else { return "" }
        if let lastSyncedAt = hermesConversationState?.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: Date()))"
        }
        return hermesConversationState == nil ? "Attach Hermes" : "Auto-sync on"
    case .syncing:
        return "Syncing..."
    case .sending:
        return "Sending..."
    case .running:
        return "Hermes is running"
    case .waitingForApproval:
        return "Waiting for approval"
    case .staleSession:
        return "Session needs repair"
    case .disconnected:
        return "Hermes disconnected"
    case .error(let message):
        return message
    }
}
```

- [ ] **Step 3: Change activation to load or show setup**

In `activateHermesConversation()`, replace the `loadOrCreateMainBrain()` path with:

```swift
private func activateHermesConversation() async {
    do {
        guard let mainBrain = try agentChatRegistry.loadMainBrain() else {
            saveCurrentConversation()
            currentConversationID = currentConversationID ?? UUID()
            messages = []
            hermesConversationState = nil
            hermesSyncStatus = .notAttached
            return
        }

        saveCurrentConversation()
        currentConversationID = mainBrain.conversationID
        if let loadedMessages = storage.loadMessages(for: mainBrain.conversationID) {
            messages = loadedMessages
        } else {
            messages = []
        }
        hermesConversationState = HermesConversationState(
            conversationID: mainBrain.conversationID,
            runtimeID: mainBrain.runtimeID,
            activeRuntimeSessionID: mainBrain.activeRuntimeSessionID,
            runtimeSessionLineage: mainBrain.runtimeSessionLineage,
            title: mainBrain.title,
            source: nil,
            lastSyncedAt: nil
        )
    } catch {
        logger.error("Failed to load Cider Main Brain: \(error.localizedDescription, privacy: .public)")
        hermesSyncStatus = .error(error.localizedDescription)
        return
    }

    await syncHermesConversation(attachIfNeeded: false)
}
```

- [ ] **Step 4: Add explicit attach and repair commands**

Add these `@MainActor` methods to `AIAssistantViewModel`:

```swift
func attachLatestHermesTelegramSession() {
    guard runtimeSelection == .hermes, !hermesSyncInFlight, !isStreaming else { return }
    Task {
        hermesSyncStatus = .syncing
        do {
            let conversationID = currentConversationID ?? UUID()
            currentConversationID = conversationID
            let result = try await hermesSessionService.attachLatestTelegramConversation(
                conversationID: conversationID
            )
            hermesConversationState = result.state
            _ = try agentChatRegistry.createMainBrain(from: result.state)
            messages = result.messages
            hermesSyncStatus = .idle
            saveCurrentConversation()
            requestScrollToBottom()
        } catch {
            logger.error("Hermes attach error: \(error.localizedDescription, privacy: .public)")
            hermesSyncStatus = .error(error.localizedDescription)
        }
    }
}

func relinkMainBrainToActiveHermesSession() {
    guard runtimeSelection == .hermes,
          hermesConversationState != nil,
          !hermesSyncInFlight,
          !isStreaming
    else { return }
    Task {
        await syncHermesConversation(attachIfNeeded: false)
    }
}

func clearHermesError() {
    if case .error = hermesSyncStatus {
        hermesSyncStatus = hermesConversationState == nil ? .notAttached : .idle
    }
}
```

- [ ] **Step 5: Keep send from auto-attaching silently**

In `ensureHermesConversationState(attachIfNeeded:)`, keep `attachIfNeeded` false for normal activation and sends that have no state. When no state exists, throw:

```swift
guard attachIfNeeded, let conversationID = currentConversationID else {
    throw HermesSessionClientError.sessionNotFound("Cider Main Brain is not attached to Hermes")
}
```

In `sendViaHermes(_:)`, call:

```swift
let state = try await ensureHermesConversationState(attachIfNeeded: false)
```

- [ ] **Step 6: Add compact UI actions**

In `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`, add Hermes actions to `drawerActionsSection`:

```swift
if viewModel.runtimeSelection == .hermes {
    drawerActionButton(title: "Attach latest Telegram", systemImage: "link") {
        viewModel.attachLatestHermesTelegramSession()
        showConversationList = false
    }

    drawerActionButton(title: "Relink session", systemImage: "arrow.triangle.2.circlepath") {
        viewModel.relinkMainBrainToActiveHermesSession()
        showConversationList = false
    }

    drawerActionButton(title: "Sync now", systemImage: hermesSyncIcon) {
        viewModel.syncHermesConversation()
        showConversationList = false
    }
}
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
swift test --filter CiderAgentChatRegistryTests
swift test --filter HermesSessionClientTests
```

Expected: both filters pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add Sources/Cider/ViewModels/AIAssistantViewModel.swift Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift Tests/CiderTests/CiderAgentChatRegistryTests.swift
git commit -m "feat: add explicit Hermes attach flow"
```

---

## Task 3: Add Hermes API Capability Probe

**Purpose:** Cider should discover whether the supported Hermes API server is available before choosing CLI fallback.

**Files:**
- Create: `Sources/Cider/Services/Agent/HermesAPIClient.swift`
- Create: `Tests/CiderTests/HermesAPIClientTests.swift`
- Modify: `Docs/Architecture/AGENT_SERVICE.md`

- [ ] **Step 1: Add API models and client skeleton**

Create `Sources/Cider/Services/Agent/HermesAPIClient.swift`:

```swift
import Foundation

struct HermesAPICapabilities: Decodable, Equatable, Sendable {
    struct Features: Decodable, Equatable, Sendable {
        let chatCompletions: Bool
        let chatCompletionsStreaming: Bool
        let responsesAPI: Bool
        let responsesStreaming: Bool
        let runSubmission: Bool
        let runStatus: Bool
        let runEventsSSE: Bool
        let runStop: Bool
        let toolProgressEvents: Bool
        let sessionContinuityHeader: String?

        enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case chatCompletionsStreaming = "chat_completions_streaming"
            case responsesAPI = "responses_api"
            case responsesStreaming = "responses_streaming"
            case runSubmission = "run_submission"
            case runStatus = "run_status"
            case runEventsSSE = "run_events_sse"
            case runStop = "run_stop"
            case toolProgressEvents = "tool_progress_events"
            case sessionContinuityHeader = "session_continuity_header"
        }
    }

    let object: String
    let platform: String
    let model: String
    let features: Features
}

enum HermesAPIClientError: Error, LocalizedError, Equatable {
    case unavailable
    case invalidResponse(Int)
    case missingRequiredCapabilities

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Hermes API server is not available"
        case .invalidResponse(let status):
            return "Hermes API server returned HTTP \(status)"
        case .missingRequiredCapabilities:
            return "Hermes API server does not support Runs/SSE"
        }
    }
}

struct HermesAPIClient: Sendable {
    var baseURL: URL
    var apiKey: String?
    var session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8642")!,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func capabilities() async throws -> HermesAPICapabilities {
        var request = URLRequest(url: baseURL.appending(path: "v1/capabilities"))
        request.httpMethod = "GET"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesAPIClientError.unavailable
        }
        guard http.statusCode == 200 else {
            throw HermesAPIClientError.invalidResponse(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(HermesAPICapabilities.self, from: data)
        guard decoded.features.runSubmission,
              decoded.features.runStatus,
              decoded.features.runEventsSSE
        else {
            throw HermesAPIClientError.missingRequiredCapabilities
        }
        return decoded
    }
}
```

- [ ] **Step 2: Add pure decode tests**

Create `Tests/CiderTests/HermesAPIClientTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct HermesAPIClientTests {
    @Test("capabilities decode Hermes Runs and SSE support")
    func capabilitiesDecodeRunsSupport() throws {
        let json = """
        {
          "object": "hermes.api_server.capabilities",
          "platform": "hermes-agent",
          "model": "hermes-agent",
          "features": {
            "chat_completions": true,
            "chat_completions_streaming": true,
            "responses_api": true,
            "responses_streaming": true,
            "run_submission": true,
            "run_status": true,
            "run_events_sse": true,
            "run_stop": true,
            "tool_progress_events": true,
            "session_continuity_header": "X-Hermes-Session-Id",
            "cors": false
          }
        }
        """

        let decoded = try JSONDecoder().decode(HermesAPICapabilities.self, from: Data(json.utf8))

        #expect(decoded.object == "hermes.api_server.capabilities")
        #expect(decoded.platform == "hermes-agent")
        #expect(decoded.features.runSubmission)
        #expect(decoded.features.runStatus)
        #expect(decoded.features.runEventsSSE)
        #expect(decoded.features.runStop)
        #expect(decoded.features.sessionContinuityHeader == "X-Hermes-Session-Id")
    }
}
```

- [ ] **Step 3: Run the new test and verify it passes**

Run:

```bash
swift test --filter HermesAPIClientTests
```

Expected: the decode test passes.

- [ ] **Step 4: Document local Hermes API enablement**

Add this section to `Docs/Architecture/AGENT_SERVICE.md` near the Hermes bridge note:

### Hermes API Server Discovery

Preferred Cider transport is Hermes API server Runs/SSE when available:

- `GET /v1/capabilities`
- `POST /v1/runs`
- `GET /v1/runs/{run_id}`
- `GET /v1/runs/{run_id}/events`
- `POST /v1/runs/{run_id}/stop`

Local enablement:

```bash
printf '\nAPI_SERVER_ENABLED=true\nAPI_SERVER_KEY=change-me-local-dev\n' >> ~/.hermes/.env
hermes gateway restart
curl -H 'Authorization: Bearer change-me-local-dev' http://127.0.0.1:8642/v1/capabilities
```

Cider must probe capabilities at runtime and fall back to CLI/export sync when the API server is disabled, unavailable, or missing Runs/SSE support.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/HermesAPIClient.swift Tests/CiderTests/HermesAPIClientTests.swift Docs/Architecture/AGENT_SERVICE.md
git commit -m "feat: probe Hermes API capabilities"
```

---

## Task 4: Add Transport Seam And Run Event Reducer

**Purpose:** Move Cider away from hardwired CLI send logic without removing the working fallback.

**Files:**
- Create: `Sources/Cider/Services/Agent/HermesBridgeTransport.swift`
- Create: `Tests/CiderTests/HermesBridgeTransportTests.swift`

- [ ] **Step 1: Define transport and event types**

Create `Sources/Cider/Services/Agent/HermesBridgeTransport.swift`:

```swift
import Foundation

enum HermesBridgeAvailability: Equatable, Sendable {
    case apiRuns
    case cliFallback
    case unavailable(String)
}

enum HermesRunStatus: Equatable, Sendable {
    case queued
    case running(runID: String)
    case waitingForApproval(String?)
    case completed(String)
    case failed(String)
    case cancelled
}

enum HermesRunEvent: Equatable, Sendable {
    case messageDelta(String)
    case toolStarted(name: String?, preview: String?)
    case toolCompleted(name: String?, isError: Bool)
    case reasoningAvailable(String)
    case completed(output: String)
    case failed(String)
    case cancelled
}

struct HermesRunSnapshot: Equatable, Sendable {
    var status: HermesRunStatus
    var visibleText: String
    var toolSummary: String?

    static let empty = HermesRunSnapshot(status: .queued, visibleText: "", toolSummary: nil)

    func reducing(_ event: HermesRunEvent) -> HermesRunSnapshot {
        var next = self
        switch event {
        case .messageDelta(let delta):
            next.visibleText += delta
        case .toolStarted(let name, let preview):
            next.toolSummary = preview ?? name
        case .toolCompleted(let name, let isError):
            if isError {
                next.toolSummary = "\(name ?? "Tool") failed"
            }
        case .reasoningAvailable:
            break
        case .completed(let output):
            next.status = .completed(output)
            if next.visibleText.isEmpty {
                next.visibleText = output
            }
        case .failed(let message):
            next.status = .failed(message)
        case .cancelled:
            next.status = .cancelled
        }
        return next
    }
}

protocol HermesBridgeTransport: Sendable {
    func availability() async -> HermesBridgeAvailability
    func send(text: String, state: HermesConversationState, history: [AIAssistantMessage]) async throws -> HermesBridgeSendResult
    func stop(runID: String) async throws
}

struct HermesBridgeSendResult: Sendable {
    let state: HermesConversationState
    let messages: [AIAssistantMessage]
}
```

- [ ] **Step 2: Add reducer tests**

Create `Tests/CiderTests/HermesBridgeTransportTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct HermesBridgeTransportTests {
    @Test("run snapshot accumulates message deltas and final output")
    func runSnapshotAccumulatesDeltas() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.messageDelta("Hello"))
            .reducing(.messageDelta(", Cider"))
            .reducing(.completed(output: "Hello, Cider"))

        #expect(snapshot.visibleText == "Hello, Cider")
        #expect(snapshot.status == .completed("Hello, Cider"))
    }

    @Test("run snapshot uses final output when no deltas arrived")
    func runSnapshotUsesFinalOutputWhenNoDeltasArrived() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.completed(output: "Done"))

        #expect(snapshot.visibleText == "Done")
        #expect(snapshot.status == .completed("Done"))
    }

    @Test("run snapshot tracks tool preview separately from assistant text")
    func runSnapshotTracksToolPreviewSeparately() {
        let snapshot = HermesRunSnapshot.empty
            .reducing(.toolStarted(name: "terminal", preview: "swift test"))
            .reducing(.messageDelta("Tests passed"))

        #expect(snapshot.visibleText == "Tests passed")
        #expect(snapshot.toolSummary == "swift test")
    }
}
```

- [ ] **Step 3: Run transport tests**

Run:

```bash
swift test --filter HermesBridgeTransportTests
```

Expected: all reducer tests pass.

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/HermesBridgeTransport.swift Tests/CiderTests/HermesBridgeTransportTests.swift
git commit -m "feat: add Hermes bridge transport seam"
```

---

## Task 5: Implement Hermes API Runs Transport

**Purpose:** Send Cider-origin turns through Hermes Runs/SSE when available.

**Files:**
- Modify: `Sources/Cider/Services/Agent/HermesAPIClient.swift`
- Create: `Sources/Cider/Services/Agent/HermesRunTransport.swift`
- Modify: `Tests/CiderTests/HermesAPIClientTests.swift`
- Modify: `Tests/CiderTests/HermesBridgeTransportTests.swift`

- [ ] **Step 1: Add run request/response/event decoding**

Add to `HermesAPIClient.swift`:

```swift
struct HermesRunCreateResponse: Decodable, Equatable, Sendable {
    let runID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

struct HermesRunStatusResponse: Decodable, Equatable, Sendable {
    let object: String?
    let runID: String
    let status: String
    let sessionID: String?
    let output: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case object
        case runID = "run_id"
        case status
        case sessionID = "session_id"
        case output
        case error
    }
}

struct HermesRunSSEEvent: Decodable, Equatable, Sendable {
    let event: String
    let runID: String?
    let delta: String?
    let output: String?
    let error: String?
    let tool: String?
    let preview: String?

    enum CodingKeys: String, CodingKey {
        case event
        case runID = "run_id"
        case delta
        case output
        case error
        case tool
        case preview
    }

    var bridgeEvent: HermesRunEvent? {
        switch event {
        case "message.delta":
            return .messageDelta(delta ?? "")
        case "tool.started":
            return .toolStarted(name: tool, preview: preview)
        case "tool.completed":
            return .toolCompleted(name: tool, isError: false)
        case "reasoning.available":
            return .reasoningAvailable(preview ?? "")
        case "run.completed":
            return .completed(output: output ?? "")
        case "run.failed":
            return .failed(error ?? "Hermes run failed")
        case "run.cancelled":
            return .cancelled
        default:
            return nil
        }
    }
}

enum HermesSSEParser {
    static func events(from data: Data) throws -> [HermesRunSSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return try text
            .components(separatedBy: "\n\n")
            .compactMap { block -> HermesRunSSEEvent? in
                let line = block
                    .components(separatedBy: "\n")
                    .first { $0.hasPrefix("data: ") }
                guard let payload = line?.dropFirst("data: ".count),
                      let payloadData = String(payload).data(using: .utf8)
                else { return nil }
                return try decoder.decode(HermesRunSSEEvent.self, from: payloadData)
            }
    }
}
```

- [ ] **Step 2: Add API methods**

Add methods to `HermesAPIClient`:

```swift
func createRun(input: String, sessionID: String?) async throws -> HermesRunCreateResponse {
    var request = URLRequest(url: baseURL.appending(path: "v1/runs"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey, !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    var body: [String: Any] = ["input": input]
    if let sessionID, !sessionID.isEmpty {
        body["session_id"] = sessionID
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw HermesAPIClientError.unavailable
    }
    guard http.statusCode == 202 else {
        throw HermesAPIClientError.invalidResponse(http.statusCode)
    }
    return try JSONDecoder().decode(HermesRunCreateResponse.self, from: data)
}

func runStatus(runID: String) async throws -> HermesRunStatusResponse {
    var request = URLRequest(url: baseURL.appending(path: "v1/runs/\(runID)"))
    request.httpMethod = "GET"
    if let apiKey, !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw HermesAPIClientError.unavailable
    }
    guard http.statusCode == 200 else {
        throw HermesAPIClientError.invalidResponse(http.statusCode)
    }
    return try JSONDecoder().decode(HermesRunStatusResponse.self, from: data)
}

func stopRun(runID: String) async throws {
    var request = URLRequest(url: baseURL.appending(path: "v1/runs/\(runID)/stop"))
    request.httpMethod = "POST"
    if let apiKey, !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let (_, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw HermesAPIClientError.unavailable
    }
    guard http.statusCode == 200 else {
        throw HermesAPIClientError.invalidResponse(http.statusCode)
    }
}
```

- [ ] **Step 3: Test SSE parsing**

Add to `HermesAPIClientTests.swift`:

```swift
@Test("SSE parser extracts Hermes run events")
func sseParserExtractsRunEvents() throws {
    let sse = """
    data: {"event":"message.delta","run_id":"run_1","delta":"Hel"}

    data: {"event":"message.delta","run_id":"run_1","delta":"lo"}

    data: {"event":"tool.started","run_id":"run_1","tool":"terminal","preview":"pwd"}

    data: {"event":"run.completed","run_id":"run_1","output":"Hello"}

    """

    let events = try HermesSSEParser.events(from: Data(sse.utf8))
    let bridgeEvents = events.compactMap(\.bridgeEvent)

    #expect(bridgeEvents == [
        .messageDelta("Hel"),
        .messageDelta("lo"),
        .toolStarted(name: "terminal", preview: "pwd"),
        .completed(output: "Hello")
    ])
}
```

- [ ] **Step 4: Create API Runs transport shell**

Create `Sources/Cider/Services/Agent/HermesRunTransport.swift`:

```swift
import Foundation

struct HermesRunTransport: HermesBridgeTransport {
    let apiClient: HermesAPIClient
    let fallbackService: HermesSessionService

    init(
        apiClient: HermesAPIClient = HermesAPIClient(),
        fallbackService: HermesSessionService = HermesSessionService()
    ) {
        self.apiClient = apiClient
        self.fallbackService = fallbackService
    }

    func availability() async -> HermesBridgeAvailability {
        do {
            _ = try await apiClient.capabilities()
            return .apiRuns
        } catch {
            return .cliFallback
        }
    }

    func send(
        text: String,
        state: HermesConversationState,
        history: [AIAssistantMessage]
    ) async throws -> HermesBridgeSendResult {
        switch await availability() {
        case .apiRuns:
            let created = try await apiClient.createRun(input: text, sessionID: state.activeRuntimeSessionID)
            var latest = HermesRunSnapshot(status: .running(runID: created.runID), visibleText: "", toolSummary: nil)
            var status = try await apiClient.runStatus(runID: created.runID)
            while status.status == "queued" || status.status == "running" || status.status == "stopping" {
                try await Task.sleep(for: .milliseconds(500))
                status = try await apiClient.runStatus(runID: created.runID)
            }
            if status.status == "completed" {
                latest = latest.reducing(.completed(output: status.output ?? ""))
                let assistant = AIAssistantMessage(
                    role: .assistant,
                    content: latest.visibleText,
                    sourceID: "hermes-run:\(created.runID)",
                    sourceSessionID: status.sessionID ?? state.activeRuntimeSessionID,
                    sourceName: "Hermes"
                )
                var nextState = state
                if let sessionID = status.sessionID, !sessionID.isEmpty {
                    nextState.activeRuntimeSessionID = sessionID
                    nextState.runtimeSessionLineage = state.runtimeSessionLineage.contains(sessionID)
                        ? state.runtimeSessionLineage
                        : state.runtimeSessionLineage + [sessionID]
                }
                nextState.lastSyncedAt = Date()
                return HermesBridgeSendResult(state: nextState, messages: history + [assistant])
            }
            throw HermesSessionClientError.hermesCommandFailed(status.error ?? "Hermes run \(status.status)")
        case .cliFallback:
            let result = try await fallbackService.send(text: text, state: state, existingMessages: history)
            return HermesBridgeSendResult(state: result.state, messages: result.messages)
        case .unavailable(let message):
            throw HermesSessionClientError.hermesCommandFailed(message)
        }
    }

    func stop(runID: String) async throws {
        try await apiClient.stopRun(runID: runID)
    }
}
```

This shell polls status first. Streaming UI is added in Task 6 after the app can choose API Runs safely.

- [ ] **Step 5: Run API and transport tests**

Run:

```bash
swift test --filter HermesAPIClientTests
swift test --filter HermesBridgeTransportTests
```

Expected: both filters pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/HermesAPIClient.swift Sources/Cider/Services/Agent/HermesRunTransport.swift Tests/CiderTests/HermesAPIClientTests.swift Tests/CiderTests/HermesBridgeTransportTests.swift
git commit -m "feat: add Hermes API runs transport"
```

---

## Task 6: Wire View Model To Transport With Safe Busy State

**Purpose:** Cider should send through the transport seam and prevent overlapping Cider-origin turns.

**Files:**
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift`
- Test: `Tests/CiderTests/HermesBridgeTransportTests.swift`

- [ ] **Step 1: Add in-process turn coordinator**

Add this actor near the Hermes status types in `AIAssistantViewModel.swift` or move it to `HermesBridgeTransport.swift` if preferred:

```swift
actor HermesTurnCoordinator {
    static let shared = HermesTurnCoordinator()
    private var activeTurnID: UUID?

    func beginTurn() throws -> UUID {
        if activeTurnID != nil {
            throw HermesSessionClientError.hermesCommandFailed("Hermes is already handling a Cider message")
        }
        let id = UUID()
        activeTurnID = id
        return id
    }

    func endTurn(_ id: UUID) {
        guard activeTurnID == id else { return }
        activeTurnID = nil
    }
}
```

- [ ] **Step 2: Add transport dependencies**

In `AIAssistantViewModel`, add:

```swift
private let hermesBridgeTransport: HermesBridgeTransport
private let hermesTurnCoordinator: HermesTurnCoordinator
```

Update the initializer signature:

```swift
init(
    provider: AIAssistantProvider? = nil,
    agentChatRegistry: CiderAgentChatRegistry = .shared,
    hermesBridgeTransport: HermesBridgeTransport = HermesRunTransport(),
    hermesTurnCoordinator: HermesTurnCoordinator = .shared
) {
    self.hermesBridgeTransport = hermesBridgeTransport
    self.hermesTurnCoordinator = hermesTurnCoordinator
    ...
}
```

- [ ] **Step 3: Route send through the bridge**

Inside `sendViaHermes(_:)`, replace the `runSendCommand` plus final sync block with:

```swift
let turnID = try await hermesTurnCoordinator.beginTurn()
defer {
    Task {
        await hermesTurnCoordinator.endTurn(turnID)
    }
}

let state = try await ensureHermesConversationState(attachIfNeeded: false)
let pendingMessage = AIAssistantMessage(
    role: .user,
    content: text,
    sourceID: "hermes:pending:\(UUID().uuidString)",
    sourceName: "Hermes Pending"
)
messages.append(pendingMessage)
requestScrollToBottom()

let existingMessages = messages.filter { $0.id != pendingMessage.id }
let result = try await hermesBridgeTransport.send(
    text: text,
    state: state,
    history: existingMessages + [AIAssistantMessage(role: .user, content: text, sourceName: "Hermes")]
)
applyHermesSyncResult(HermesSyncResult(state: result.state, messages: result.messages), forceMessages: true)
hermesSyncStatus = .idle
saveCurrentConversation()
```

- [ ] **Step 4: Make UI copy honest**

In `hermesStatusTitle`, keep `.sending` as `Sending...` and `.running` as `Hermes is running`.

In `send(_:)`, keep this guard:

```swift
guard !trimmed.isEmpty, !isStreaming else { return }
```

This prevents overlapping Cider sends. It does not claim to lock Telegram or CLI.

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter HermesBridgeTransportTests
swift test --filter HermesSessionClientTests
swift test --filter CiderAgentChatRegistryTests
```

Expected: all focused tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/Cider/ViewModels/AIAssistantViewModel.swift Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift Tests/CiderTests/HermesBridgeTransportTests.swift
git commit -m "feat: route Hermes sends through bridge transport"
```

---

## Task 7: Add Streaming SSE UI Path

**Purpose:** When API Runs are available, Cider should show live text/tool progress from Hermes events instead of waiting for final export or polling session files.

**Files:**
- Modify: `Sources/Cider/Services/Agent/HermesAPIClient.swift`
- Modify: `Sources/Cider/Services/Agent/HermesRunTransport.swift`
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify: `Tests/CiderTests/HermesAPIClientTests.swift`

- [ ] **Step 1: Add event streaming API**

Add to `HermesAPIClient`:

```swift
func runEvents(runID: String) async throws -> AsyncThrowingStream<HermesRunSSEEvent, Error> {
    var request = URLRequest(url: baseURL.appending(path: "v1/runs/\(runID)/events"))
    request.httpMethod = "GET"
    if let apiKey, !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw HermesAPIClientError.unavailable
                }
                guard http.statusCode == 200 else {
                    throw HermesAPIClientError.invalidResponse(http.statusCode)
                }

                var block = ""
                for try await line in bytes.lines {
                    if line.isEmpty {
                        if let dataLine = block
                            .components(separatedBy: "\n")
                            .first(where: { $0.hasPrefix("data: ") }) {
                            let payload = String(dataLine.dropFirst("data: ".count))
                            if let data = payload.data(using: .utf8) {
                                let event = try JSONDecoder().decode(HermesRunSSEEvent.self, from: data)
                                continuation.yield(event)
                            }
                        }
                        block = ""
                    } else {
                        block += line + "\n"
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

- [ ] **Step 2: Add streaming send variant**

Add to `HermesRunTransport`:

```swift
func sendStreaming(
    text: String,
    state: HermesConversationState,
    onEvent: @escaping @Sendable (HermesRunEvent) async -> Void
) async throws -> HermesRunStatusResponse {
    let created = try await apiClient.createRun(input: text, sessionID: state.activeRuntimeSessionID)
    var finalStatus: HermesRunStatusResponse?
    let stream = try await apiClient.runEvents(runID: created.runID)
    for try await event in stream {
        if let bridgeEvent = event.bridgeEvent {
            await onEvent(bridgeEvent)
        }
    }
    finalStatus = try await apiClient.runStatus(runID: created.runID)
    return finalStatus!
}
```

- [ ] **Step 3: Consume stream events in the view model**

In `sendViaHermes(_:)`, when the concrete transport is `HermesRunTransport` and availability is `.apiRuns`, call `sendStreaming`. Reduce events into `streamingText`, `displayedStreamingText`, and final messages. Use this event handler:

```swift
var snapshot = HermesRunSnapshot(status: .queued, visibleText: "", toolSummary: nil)
let status = try await runTransport.sendStreaming(text: text, state: state) { [weak self] event in
    await MainActor.run {
        snapshot = snapshot.reducing(event)
        switch event {
        case .messageDelta:
            self?.streamingText = snapshot.visibleText
        case .toolStarted:
            self?.hasLiveHermesResponseForActiveSend = true
        case .completed:
            self?.streamingText = snapshot.visibleText
        case .failed(let message):
            self?.hermesSyncStatus = .error(message)
        case .cancelled:
            self?.hermesSyncStatus = .idle
        case .toolCompleted, .reasoningAvailable:
            break
        }
        self?.requestScrollToBottom()
    }
}
```

After completion, append the final assistant message using `status.output`.

- [ ] **Step 4: Keep CLI fallback unchanged**

If availability is `.cliFallback`, keep the Task 6 send path using `hermesBridgeTransport.send(...)`.

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter HermesAPIClientTests
swift test --filter HermesBridgeTransportTests
swift test --filter HermesSessionClientTests
```

Expected: all focused tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/HermesAPIClient.swift Sources/Cider/Services/Agent/HermesRunTransport.swift Sources/Cider/ViewModels/AIAssistantViewModel.swift Tests/CiderTests/HermesAPIClientTests.swift
git commit -m "feat: stream Hermes run events into chat"
```

---

## Task 8: Add Stop And Repair UX

**Purpose:** Cider should expose run stop and session repair as visible controls.

**Files:**
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift`

- [ ] **Step 1: Track active Hermes run ID**

Add to `AIAssistantViewModel`:

```swift
@Published private(set) var activeHermesRunID: String?
```

Set it when a Runs API send starts and clear it in every completion, cancellation, and error path.

- [ ] **Step 2: Stop active Hermes run**

Add:

```swift
func stopHermesRun() {
    guard let runID = activeHermesRunID else {
        stopStreaming()
        return
    }
    Task {
        do {
            try await hermesBridgeTransport.stop(runID: runID)
        } catch {
            logger.error("Hermes stop error: \(error.localizedDescription, privacy: .public)")
        }
        activeHermesRunID = nil
        stopStreaming()
    }
}
```

Update the Hermes composer stop action to call `stopHermesRun()` instead of `stopStreaming()`.

- [ ] **Step 3: Add session repair copy in drawer**

In `drawerCurrentSection`, when `viewModel.hermesConversationState == nil`, show a compact status line:

```swift
Text("No Hermes session attached")
    .font(CiderFont.caption)
    .foregroundColor(CiderColors.warning)
```

Keep the action buttons from Task 2 visible.

- [ ] **Step 4: Add stale session behavior**

When `syncHermesConversation(attachIfNeeded:)` catches `HermesSessionClientError.sessionNotFound`, set:

```swift
hermesSyncStatus = .staleSession(error.localizedDescription)
```

The drawer's `Relink session` and `Attach latest Telegram` actions are the repair path.

- [ ] **Step 5: Manual QA**

Run Cider and verify:

```text
1. Hermes mode with no registry shows Attach Hermes.
2. Attach latest Telegram creates cider.main without seeded IDs.
3. Sync shows the active short session ID.
4. Send disables the composer while running.
5. Stop appears while an API run is active and calls /v1/runs/{run_id}/stop.
6. Invalid stored session shows Session needs repair.
7. Relink/sync recovers when the session lineage exists.
```

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/Cider/ViewModels/AIAssistantViewModel.swift Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift
git commit -m "feat: add Hermes stop and repair controls"
```

---

## Task 9: Document Source-Of-Truth And Roadmap State

**Purpose:** Future work should not confuse Cider's mirror with Hermes runtime truth.

**Files:**
- Modify: `Docs/Architecture/AGENT_SERVICE.md`
- Modify: `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
- Modify: `Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md`

- [ ] **Step 1: Add source-of-truth rule**

Add this language to `Docs/Architecture/AGENT_SERVICE.md`:

### Cider/Hermes Source Of Truth

Hermes owns runtime session continuity, tool context, memory, compaction, approvals and permission prompts, streaming/run state, and raw agent execution history. Cider owns the user-facing vault UI, stable chat identity, mirrored display history, search/index affordances, native confirmation boxes, and vault actions.

Cider may mirror Hermes messages for display, search, and offline continuity, but the mirror is not the authoritative runtime transcript. When Hermes API Runs/SSE are available, Cider should prefer that supported event contract over reading Hermes session files directly. When the API server is unavailable, Cider may use CLI/export/session-file polling as a bridge with clear fallback status.

- [ ] **Step 2: Update adaptive roadmap**

In `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`, keep bridge hardening as `Now` and make the order explicit:

**Current implementation order:**

1. Remove seeded/local-only Hermes session assumptions.
2. Add explicit attach/relink/repair flow.
3. Probe Hermes API server capabilities.
4. Prefer API Runs/SSE for send, stream, status, and stop when available.
5. Keep CLI/export/session-file polling as fallback.
6. Add native approval UI when Hermes exposes an app-client approval event and response path.

- [ ] **Step 3: Update historical Main Brain plan**

In `Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md`, add:

**Hardening follow-up:** The seeded local Hermes lineage from this plan has been replaced by the explicit attach/create/repair flow in `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`. Treat the seed IDs here as historical implementation context only.

- [ ] **Step 4: Commit**

Run:

```bash
git add Docs/Architecture/AGENT_SERVICE.md Docs/Product/CIDER_ADAPTIVE_ROADMAP.md Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md
git commit -m "docs: clarify Cider Hermes bridge ownership"
```

---

## Task 10: Add Named Hermes Chat Registry

**Purpose:** Users should be able to create named Cider/Hermes side chats for scoped work without flooding Main Brain, and then resume those chats from Telegram by explicit title.

**Files:**
- Modify: `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift`
- Modify: `Sources/Cider/Services/Agent/HermesSessionClient.swift`
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift`
- Modify: `Sources/Cider/Services/AI/AIConversationStorage.swift` if sidebar summaries need registry metadata
- Modify/Add: `Tests/CiderTests/CiderAgentChatRegistryTests.swift`
- Modify/Add: `Tests/CiderTests/HermesSessionClientTests.swift`

**Product rule:** Cider must store its own stable logical chat record and also write the user-facing name into Hermes as the actual session title. A Cider-only display name is not enough.

**Naming rule:** No special Telegram naming convention is required. Use a human-readable, unique Hermes title such as `Cider Dashboard Worktree` or `Cider Scratchpad`. Keep titles trimmed, whitespace-collapsed, control-character-free, and under Hermes' 100-character title limit. Avoid generic titles like `Dashboard` or `Scratchpad`.

**Cross-client rule:** Telegram may not show Cider-created sessions in a bare `/resume` list if that list is filtered by source, but explicit resume by title should work:

```text
/resume Cider Dashboard Worktree
```

- [ ] **Step 1: Extend chat records for named Hermes chats**

Update `CiderAgentChatRecord` to support:

```swift
var stableID: String                 // e.g. cider.dashboard-worktree
var title: String                    // Cider display name
var hermesTitle: String?             // e.g. Cider Dashboard Worktree
var kind: String                     // main-brain, hermes-chat, project-chat, scratchpad
var conversationID: UUID
var runtimeID: String
var activeRuntimeSessionID: String   // may be empty until first send
var runtimeSessionLineage: [String]
var scope: String?                   // global, cider, project, scratchpad
var archived: Bool
var createdAt: Date
var updatedAt: Date
var defaultInCider: Bool
```

Keep backward decoding compatible with existing `cider.main.json` by giving new fields defaults when missing.

- [ ] **Step 2: Turn the registry into a real named chat registry**

Add APIs:

```swift
func listChats(includeArchived: Bool = false) throws -> [CiderAgentChatRecord]
func loadChat(stableID: String) throws -> CiderAgentChatRecord?
func createHermesChat(title: String, scope: String?) throws -> CiderAgentChatRecord
func updateChat(_ record: CiderAgentChatRecord) throws
func archiveChat(stableID: String) throws
func renameChat(stableID: String, title: String) throws -> CiderAgentChatRecord
```

Keep `loadMainBrain()`, `createMainBrain(from:)`, and `updateMainBrain(from:)` as convenience wrappers over the generalized registry.

- [ ] **Step 3: Generate stable IDs from titles**

Create stable IDs like:

```text
cider.dashboard-worktree
cider.web-review
cider.scratchpad
```

Rules:

- lowercase,
- ASCII slug where possible,
- collapse whitespace/punctuation to hyphens,
- prefix with `cider.`,
- preserve uniqueness by appending `-2`, `-3`, etc.,
- never change the stable ID when the user renames the chat.

- [ ] **Step 4: Create Cider chat immediately, create Hermes session on first message**

Flow:

```text
User clicks New Hermes Chat
→ Cider asks for a name
→ Cider creates CiderAgentChatRecord with empty activeRuntimeSessionID
→ Cider opens that local chat
→ first send runs Hermes with source cider
→ Cider captures the new Hermes session ID
→ Cider renames that Hermes session to the record's hermesTitle
→ Cider stores activeRuntimeSessionID and lineage
```

Do not create empty Hermes sessions just because the user made a named Cider chat.

- [ ] **Step 5: Rename the actual Hermes session after first send**

Add a service method equivalent to:

```swift
func renameSession(sessionID: String, title: String) async throws
```

CLI fallback:

```bash
hermes sessions rename <session_id> "Cider Dashboard Worktree"
```

Call it after a first-send-created session and whenever the user renames a chat that already has a backing Hermes session.

- [ ] **Step 6: Add Copy Telegram resume command**

Expose an action for named Hermes chats:

```text
Copy Telegram resume command
```

It copies:

```text
/resume Cider Dashboard Worktree
```

Use the Hermes-visible title, not the Cider stable ID.

- [ ] **Step 7: Update the chat switcher**

The Cider chat list should show registry-backed Hermes chats alongside regular chat summaries, with Main Brain pinned or clearly marked. Named Hermes side chats should not duplicate every sync under separate rows for each backing runtime session.

Minimum expected rows:

```text
Main Brain
Cider Dashboard Worktree
Cider Web Review
Cider Scratchpad
```

- [ ] **Step 8: Preserve Main Brain behavior**

Main Brain remains `cider.main` and continues to use the explicit attach/latest Telegram behavior already implemented. Do not turn Main Brain into a random side chat or require a new name.

- [ ] **Step 9: Test named registry and Hermes rename behavior**

Cover:

1. Creating a named chat stores a stable Cider record with no Hermes session yet.
2. Stable IDs are unique and do not change on rename.
3. First send fills `activeRuntimeSessionID` and lineage.
4. First send renames the Hermes session to `hermesTitle`.
5. Renaming a backed chat calls Hermes session rename.
6. Copy Telegram command uses `/resume <hermesTitle>`.
7. Archived chats disappear from the default list.
8. Main Brain convenience APIs still pass existing tests.

- [ ] **Step 10: Commit**

Run:

```bash
swift test --filter CiderAgentChatRegistryTests
swift test --filter HermesSessionClientTests
git add Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift Sources/Cider/Services/Agent/HermesSessionClient.swift Sources/Cider/ViewModels/AIAssistantViewModel.swift Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift Sources/Cider/Services/AI/AIConversationStorage.swift Tests/CiderTests/CiderAgentChatRegistryTests.swift Tests/CiderTests/HermesSessionClientTests.swift
git commit -m "feat: add named Hermes chats"
```

---

## Task 11: Add Cider-Native Slash Command Router

**Purpose:** Make Cider chat feel more like Hermes inside Cider before Runs/SSE and native approvals are fully available.

**Files:**
- Create: `Sources/Cider/Services/Agent/CiderChatCommandRouter.swift`
- Modify: `Sources/Cider/ViewModels/AIAssistantViewModel.swift`
- Modify/Add: `Tests/CiderTests/CiderChatCommandRouterTests.swift`

**Product rule:** Slash commands are a native command surface for the primary Cider brain. They should not become a large architecture project, and they should not depend on perfect Telegram/Cider transcript sync.

**V1 commands:**

```text
/help
/status
/resume [title]
/last
/summary
/checkpoint
/new
/title <title>
```

**Command behavior:**

- `/help` returns a short local assistant message listing supported commands.
- `/status` returns a local assistant message with active chat name, Hermes title, session ID short form, sync state, and transport availability if known.
- `/resume` with no title resumes `Cider`; `/resume <title>` resolves or repairs by Hermes title using the existing registry/service path.
- `/last` returns the last cached assistant response in the current Cider chat.
- `/summary` sends a normal Hermes request asking for a concise summary of the current chat unless a cached summary exists later.
- `/checkpoint` sends a normal Hermes request asking it to save durable decisions/context. Do not create a new checkpoint doc automatically in Cider for v1.
- `/new` explains that starting fresh will leave the current brain intact and requires `/new confirm` before starting a separate fresh local Hermes chat.
- `/new confirm` starts a fresh local Hermes chat using the existing `startFreshHermesSession()` behavior.
- `/title <title>` renames side chats locally and renames the backing Hermes session when one exists. On `cider.main`, v1 must preserve the canonical Hermes title `Cider` and return a local safety message instead of renaming.

**Router shape:**

```swift
struct CiderChatCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case localMessage(String)
        case resume(title: String)
        case sendToHermes(String)
        case showStatus
        case showLastResponse
        case startFreshChat
        case renameCurrentChat(String)
    }

    let name: String
    let argument: String?
    let action: Action
}
```

`CiderChatCommandRouter.parse(_:)` should return `nil` for normal messages and throw a clear parse error for unsupported slash commands.

- [ ] **Step 1: Write command parser tests**

Cover:

1. Normal messages are not commands.
2. `/help` returns `.localMessage`.
3. `/resume` defaults to `Cider`.
4. `/resume Scratchpad` preserves the title argument.
5. `/summary` becomes a Hermes prompt.
6. `/checkpoint` becomes a Hermes prompt.
7. `/new` returns a local confirmation message.
8. `/new confirm` returns `.startFreshChat`.
9. `/title Cider Scratchpad` returns `.renameCurrentChat("Cider Scratchpad")`.
10. Unknown slash commands throw an unsupported-command error.

- [ ] **Step 2: Implement `CiderChatCommandRouter`**

Keep the parser pure and independent from SwiftUI so it is easy to test.

- [ ] **Step 3: Wire the view model**

In `AIAssistantViewModel.send(_:)`, before normal Hermes send:

1. Ask the router whether the trimmed message is a command.
2. Execute local command actions without sending to Hermes.
3. Convert `.sendToHermes` actions into normal Hermes sends.
4. Reuse existing attach/relink/start-fresh/rename methods where possible.
5. Append local command output as assistant messages with `sourceName: "Cider"`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter CiderChatCommandRouterTests
swift test --filter CiderAgentChatRegistryTests
swift test --filter HermesSessionClientTests
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/Cider/Services/Agent/CiderChatCommandRouter.swift Sources/Cider/ViewModels/AIAssistantViewModel.swift Tests/CiderTests/CiderChatCommandRouterTests.swift
git commit -m "feat: add Cider chat slash commands"
```

---

## Task 11.5: Add Slash Command Discovery Popup

**Purpose:** Make the native command surface discoverable without requiring Erik to memorize every slash command.

**Files:**
- Modify: `Sources/Cider/Services/Agent/CiderChatCommandRouter.swift`
- Modify: `Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift`
- Modify/Add: `Tests/CiderTests/CiderChatCommandRouterTests.swift`

**Product rule:** This is command discovery/autocomplete only. It should reuse the existing command router metadata and should not create a second command execution path.

**Behavior:**

- When the composer draft starts with `/`, show a compact popup above the input.
- Filter commands as the user types, so `/s` shows `/status` and `/summary`.
- Each row should show the command name and a short human-readable description.
- Clicking a command fills the composer with that command.
- Commands that expect an argument, such as `/resume` and `/title`, should insert a trailing space.
- Commands that are complete by themselves, such as `/help`, `/status`, `/last`, `/summary`, `/checkpoint`, and `/new`, should not auto-send.
- Hide the popup when the draft no longer starts with `/`, after a command is selected, or after sending.
- Keep keyboard navigation as optional polish after the click-selection version works.

- [x] **Step 1: Add command metadata tests**

Extend `CiderChatCommandRouterTests` to cover:

1. The router exposes metadata for every v1 command.
2. Filtering with an empty `/` query returns the v1 command list.
3. Filtering with `s` returns `/status` and `/summary`.
4. Commands that require arguments are marked so the UI can insert a trailing space.

- [x] **Step 2: Add pure command metadata/filtering API**

Add a small metadata type to `CiderChatCommandRouter`, for example:

```swift
struct Suggestion: Equatable, Sendable {
    let name: String
    let usage: String
    let description: String
    let insertsTrailingSpace: Bool
}
```

Expose a pure filtering helper such as `suggestions(matching:)`.

- [x] **Step 3: Render the popup in `AIAssistantInputView`**

Use the input text binding to derive the current slash query. Render the popup above the input bar with existing Cider colors, tight spacing, and stable dimensions.

- [x] **Step 4: Wire row selection**

On row click, replace the draft with the selected command insertion string and refocus the composer. Do not send automatically.

- [x] **Step 5: Run focused tests and build**

Run:

```bash
swift test --filter CiderChatCommandRouterTests
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: tests and build pass.

**Implementation note, 2026-05-03:** Command metadata/filtering, click-to-insert popup UI, and approval-request event parsing are implemented. Cider can show a waiting-for-approval state from Runs/SSE events, but native approve/deny remains intentionally deferred until Hermes exposes a supported approval response endpoint.

---

## Task 12: Verification

**Purpose:** Prove the hardened bridge did not break existing AI, Hermes parsing, or floating surface behavior.

**Files:**
- Test-only.

- [x] **Step 1: Run focused Hermes tests**

Run:

```bash
swift test --filter CiderAgentChatRegistryTests
swift test --filter HermesSessionClientTests
swift test --filter HermesAPIClientTests
swift test --filter HermesBridgeTransportTests
```

Expected: every focused filter passes.

- [x] **Step 2: Run surface recall tests**

Run:

```bash
swift test --filter CiderSurfaceRecallCoordinatorTests
```

Expected: surface recall tests pass.

- [x] **Step 3: Run full Swift test suite**

Run:

```bash
swift test
```

Expected: full package tests pass.

- [x] **Step 4: Build app**

Run:

```bash
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 5: Manual Hermes API check**

With Hermes API server enabled, run:

```bash
curl -H 'Authorization: Bearer change-me-local-dev' http://127.0.0.1:8642/v1/capabilities
```

Expected: JSON includes `"run_submission": true`, `"run_status": true`, and `"run_events_sse": true`.

**Current result, 2026-05-03:** `127.0.0.1:8642` is not reachable on this machine, so Cider remains on the CLI/export fallback path until Hermes exposes or enables the API server locally.

**Known delivery gap, 2026-05-03:** Hermes cron automation/job results currently appear in Telegram but do not route into the Cider AI chat. Keep this as a later remote-surface delivery/import issue, not a blocker for merging the current Cider chat hardening work.

- [ ] **Step 6: Manual Cider QA**

Verify:

```text
1. Fresh registry starts unattached.
2. Attach latest Telegram creates a non-seeded cider.main record.
3. Named Hermes chat can be created without creating an empty Hermes session.
4. First send in a named Hermes chat creates/attaches a Hermes session and renames it.
5. Telegram can explicitly resume the named chat with `/resume <Hermes title>`.
6. Sending through Hermes works with API server enabled.
7. Sending through Hermes falls back to CLI/export when API server is disabled.
8. Repeated identical Hermes messages are not collapsed.
9. Live/export duplicates do not appear.
10. Stop cancels an active API run.
11. Stale session errors expose repair actions.
```

---

## Self-Review

- Spec coverage: The plan covers seeded-session removal, fresh attach behavior, named Hermes side chats resumable by Telegram title, API/Runs capability discovery, run state, streaming, stop, repair controls, dedupe preservation, and source-of-truth docs.
- Placeholder scan: The plan avoids open-ended implementation placeholders; approval UI is intentionally deferred until Hermes exposes an app-client approval response path, and the current phase documents that boundary instead of faking it.
- Type consistency: `HermesAPIClient`, `HermesRunTransport`, `HermesBridgeTransport`, `HermesRunEvent`, and `HermesRunSnapshot` are introduced before later tasks reference them.
