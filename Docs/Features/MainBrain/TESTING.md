# Main Brain Testing

**Status:** Testing and verification source of truth for Main Brain.

---

## Existing Automated Tests

Relevant tests include:

- `Tests/CiderTests/CiderAgentChatRegistryTests.swift`
- `Tests/CiderTests/HermesSessionClientTests.swift`
- `Tests/CiderTests/AIAssistantPromptTests.swift`
- `Tests/CiderTests/AgentRoutingInstructionsTests.swift`
- `Tests/CiderTests/CiderSurfaceRecallCoordinatorTests.swift`

---

## Focused Test Commands

Run focused tests when touching Main Brain identity/session behavior:

```bash
swift test --filter CiderAgentChatRegistryTests
swift test --filter HermesSessionClientTests
swift test --filter AIAssistantPromptTests
swift test --filter AgentRoutingInstructionsTests
```

Run broader verification before merging substantial changes:

```bash
swift test
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

---

## Manual QA Checklist

### Main Brain identity

- Opening Cider chat loads `cider.main`.
- Display name is `Cider`.
- Raw Hermes session IDs are not the visible identity.
- Stored runtime pointer updates after successful Hermes resume/send.
- Stale session repair follows the newest valid `Cider` continuation.

### Slash command router

- `/help` shows the v1 command list.
- `/status` shows logical chat, transport, and run/busy state.
- `/resume Cider` attaches the correct Main Brain.
- `/last` does not require a model call when a local cached response exists.
- Unknown commands show a clean local error/help message.
- `/title` cannot accidentally rename canonical `cider.main` away from `Cider`.
- `/new` preserves lineage and avoids accidental context loss.

### Transport behavior

- If Runs/SSE is unavailable, Cider falls back gracefully.
- If Runs/SSE is available, Cider can stream text and show busy state.
- Stop button calls the active transport's stop/cancel path when supported.

### Remote compatibility

- Telegram/Discord can still use `/resume Cider` when available.
- Remote transcript mirroring is not required for success.
- `/last` or `/summary` can compensate when a remote surface cannot see the prior Cider response.

---

## Regression Risks

- Accidentally treating a raw Hermes session ID as permanent identity.
- Over-coupling Cider chat to Telegram transcript sync.
- Allowing `/title` or `/new` to make the Main Brain feel lost.
- Dumping internal tool chatter into the visible chat.
- Creating durable facts only in chat transcript instead of Cider objects/docs/memory.
