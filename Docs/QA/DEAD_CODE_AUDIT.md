# Dead Code Detection Audit

Automated scan-fix-rescan loop for unused code across the codebase.
Each area requires **3 independent clean scans** before marking PASS.
Build verified with `swift build` after each removal.

**Checks:**
1. Unused private functions/variables
2. Unused imports
3. Commented-out code blocks
4. Empty extension blocks
5. Unused type definitions
6. Unused parameters

---

## Progress Tracker

| Area | Status | Removals | Clean Passes | Last Scanned |
|------|--------|----------|-------------|--------------|
| Views/AIAssistant/ | PASS | 2 removed | 3/3 | 2026-03-20 |
| Services/AI/ | PASS | 1 removed | 3/3 | 2026-03-20 |

---

## Fix Log

### 2026-03-20 — Views/AIAssistant/ + Services/AI/ (Claude Opus 4.6)

**Pass 1 — 3 dead code items found and removed:**

1. `AIAssistantBubbleView.swift` — `@State private var isHovered` + `.onHover` handler: variable was written to by hover tracking but never read in any conditional. Removed both.

2. `MLXProvider.swift` — `private var conversationHistory`: maintained (appended, trimmed) but never read for prompt building. `buildConversationPrompt()` uses the `messages` parameter from the ViewModel instead. Likely a leftover from an earlier iteration. Removed property, removed append/trim logic in `streamResponse`, updated `resetSession()`.

3. `ColorExtractionService.swift` — Tested removing `import AppKit` (only CG types used visibly), but `CGImageSourceCreateWithURL` resolves through AppKit on macOS. Import is required — reverted.

**Pass 2 — Clean.** No new dead code found.
**Pass 3 — Clean.** Confirmed.

**No old CLI wrapper remnants found** — searched for CLIProvider, TerminalProvider, ShellProvider, OllamaProvider, LlamaProvider, Process(), and general CLI/terminal/shell references. All clean.
