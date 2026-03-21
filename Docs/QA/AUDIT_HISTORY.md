# Audit History

Record of all automated audits run against the Cider codebase.

## Completed Audits

| Audit | Date | Violations Fixed | Branch | Notes |
|-------|------|-----------------|--------|-------|
| Design Token | 2026-03-18 | ~190+ | audit-fixes | Hardcoded colors → CiderColors, fonts → CiderFont, magic numbers → Spacing/Radius/Design constants. Created dozens of new design tokens. |
| Convention Enforcement | 2026-03-18 | 17 | convention-fixes | 15 NSLog → os.Logger, 1 AppleScript app name removed, 1 missing [weak self]. |
| Threading Safety | 2026-03-19 | 34 | threading-fixes | 16 Combine publishers missing .receive(on:), sync file I/O moved off main thread, force unwraps in async contexts, @MainActor on state mutations after await, NSLock → OSAllocatedUnfairLock. |
| Dead Code | 2026-03-20 | 3 | main | Removed unused `isHovered` state in AIAssistantBubbleView, unused `conversationHistory` in MLXProvider. 2 areas scanned so far. |

**Total fixes across all audits: ~243+**

## Available Loops (not yet run)

| Loop | Doc | Purpose |
|------|-----|---------|
| Docs Health | `Docs/QA/DOCS_LOOP.md` | Check docs against actual code for stale/outdated content |

## Detailed Results

Each audit has its own detailed results doc with per-area progress tracker and fix log:

- `Docs/QA/CODE_AUDIT.md` — Design token audit results
- `Docs/QA/CONVENTION_AUDIT.md` — Convention enforcement results
- `Docs/QA/THREADING_AUDIT.md` — Threading safety results
- `Docs/QA/DEAD_CODE_AUDIT.md` — Dead code detection results
