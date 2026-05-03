# Main Brain

**Status:** Active / MVP in progress  
**Owner surface:** Cider Desktop chat first; Telegram/Discord/mobile remain remote access surfaces  
**Source of truth:** This feature folder is the durable source of truth for Cider's Hermes-powered second-brain chat.

---

## Visual Map

Open the browser visual:

`Docs/Features/MainBrain/VISUAL_MAP.html`

Quick text version:

```text
Erik
 │
 ├─ Cider Desktop Chat ─────────────┐
 │                                  │
 ├─ Telegram / Discord remote ──────┤
 │                                  ▼
 │                         Cider Main Brain
 │                         logicalChatID: cider.main
 │                         Hermes title: Cider
 │                                  │
 │                                  ▼
 │                         Hermes runtime/session
 │                         current session + lineage
 │                                  │
 └──────────────────────────────────▼
                            Cider Vault objects
             bookmarks / notes / todos / events / contacts / docs / dashboard cards
```

---

## What This Feature Does

Main Brain is Cider's native Hermes-powered second-brain chat. It should let Erik talk to Cider as a personal brain that can capture, recall, organize, and resurface useful things from the vault.

The goal is **not** perfect visual sync between Cider and Telegram. The goal is:

```text
Cider chat feels like Hermes inside Cider.
```

The primary stable chat is:

- logical chat ID: `cider.main`
- display name: `Cider`
- Hermes title: `Cider`
- remote resume command: `/resume Cider`

Telegram, Discord, and future mobile clients can resume the same named brain when Erik is away, but they do not need to mirror every Cider transcript bubble.

---

## Current Code Map

### Cider chat UI

- `Sources/Cider/Views/AIAssistant/AIAssistantPanelView.swift` — main AI chat panel surface
- `Sources/Cider/Views/AIAssistant/AIAssistantInputView.swift` — input composer
- `Sources/Cider/Views/AIAssistant/AIAssistantBubbleView.swift` — chat bubble rendering
- `Sources/Cider/ViewModels/AIAssistantViewModel.swift` — chat state, runtime switching, send flow, Hermes activation

### Main Brain identity / Hermes session continuity

- `Sources/Cider/Services/Agent/CiderAgentChatRegistry.swift` — stable `cider.main` record, active runtime session pointer, lineage
- `Sources/Cider/Services/Agent/HermesSessionClient.swift` — Hermes session/state adapter
- `Sources/Cider/Services/AI/AIConversationStorage.swift` — local Cider chat transcript storage

### Agent/runtime support

- `Sources/Cider/Services/Agent/AgentOrchestrator.swift` — runtime health and orchestration
- `Sources/Cider/Services/Agent/AgentRuntime.swift` — runtime abstraction
- `Sources/Cider/Services/Agent/AgentTypes.swift` — shared agent types
- `Sources/Cider/Services/AI/AIAssistantProvider.swift` — assistant provider interface
- `Sources/Cider/Services/AI/AgentRoutingInstructions.swift` — agent routing instructions

### Remote transport compatibility

- `Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift` — Telegram bridge and remote command handling
- `Sources/Cider/Services/Channels/Telegram/TelegramModels.swift` — Telegram bridge config/state models

### Tests

- `Tests/CiderTests/CiderAgentChatRegistryTests.swift`
- `Tests/CiderTests/HermesSessionClientTests.swift`
- `Tests/CiderTests/AIAssistantPromptTests.swift`
- `Tests/CiderTests/AgentRoutingInstructionsTests.swift`

---

## User Flows

### Open Cider Main Brain

1. Erik opens Cider chat.
2. Cider loads the stable `cider.main` record.
3. Cider resolves the backing Hermes title `Cider` and current session pointer.
4. If the stored pointer is stale after compaction/continuation, Cider repairs by title/lineage.
5. The chat opens as `Cider`, regardless of raw Hermes session ID churn.

### Resume remotely

1. Erik is away from the Mac and sends `/resume Cider` in Telegram/Discord/Hermes.
2. Hermes resumes the named Cider session or latest continuation.
3. Erik can ask for `/last`, `/summary`, or continue the brain conversation.
4. Cider does not need to show every remote bubble immediately; durable results should land in Cider objects/docs.

### Capture into the vault

1. Erik sends a URL, idea, reminder, event, contact, note, or media item.
2. Main Brain decides whether this is a chat-only answer or a durable Cider object.
3. Durable objects are created or updated through supported Cider CLI/storage rails.
4. The assistant reports the object/path/action cleanly.

### Native command surface

1. Erik types a slash command in Cider chat, such as `/status`, `/last`, or `/checkpoint`.
2. Cider parses and routes the command locally when possible.
3. Commands requiring Hermes are forwarded through the active Hermes transport.
4. Unknown commands return a clean local help/error response, not a confusing model prompt.

---

## Command Quality Rules

Cider slash commands should be:

1. **Predictable:** same command works the same way in Cider and remote surfaces when possible.
2. **Safe:** commands that can lose context, rename the main brain, or mutate files should confirm when needed.
3. **Local-first:** simple UI/status commands should not require an LLM round trip.
4. **Readable:** command output should be concise, especially when bridged to Telegram.
5. **Extensible:** new commands should register in one obvious command registry.

---

## Maintenance Rules

- When Main Brain product behavior changes, update `PRODUCT.md` and this README.
- When session identity, lineage, run state, or transport behavior changes, update `ARCHITECTURE.md` and `DATA_MODEL.md`.
- When slash commands change, update `CLI.md`.
- When tests or manual QA change, update `TESTING.md`.
- When priority changes, update `ROADMAP.md`.
- When a key decision is made, append `DECISIONS.md`.
- Keep historical plans/specs linked; do not bulk-move or archive them without Erik approval.

---

## Related Docs

Durable docs:

- `Docs/Features/MainBrain/PRODUCT.md`
- `Docs/Features/MainBrain/ARCHITECTURE.md`
- `Docs/Features/MainBrain/DATA_MODEL.md`
- `Docs/Features/MainBrain/CLI.md`
- `Docs/Features/MainBrain/TESTING.md`
- `Docs/Features/MainBrain/ROADMAP.md`
- `Docs/Features/MainBrain/DECISIONS.md`

Historical/source docs:

- `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
- `Docs/Product/COMPUTER_AGENT_CHAT_APP_CONCEPT.md`
- `Docs/Product/COMPUTER_AGENT_CHAT_APP_MVP_SPEC.md`
- `Docs/superpowers/plans/2026-05-01-cider-main-brain-ai-surface.md`
- `Docs/superpowers/plans/2026-05-02-cider-hermes-bridge-hardening.md`
- `Docs/Vault/Checkpoints/2026-05-02-cider-hermes-session-lineage-sync.md`
