# AI Chat in Cider

> **Status:** v1 built and working. Conversation persistence in progress.

---

## What It Is

A native chat interface embedded in Cider that talks to CLI-based AI tools (Claude, Gemini, Codex) and optionally doubles as a shell. No browser tabs, no separate apps — AI access from a floating panel that's always one double-tap away.

## What's Built (v1)

### Chat UI
- Native SwiftUI chat bubble interface. Replaced the earlier SwiftTerm terminal approach entirely — no terminal emulator dependency.
- User messages on the right, assistant responses on the left, standard chat layout.
- Model selector pills at the bottom to switch between backends: Claude, Gemini, Codex. Shell is accessible via a chevron expander for power users.

### Two Modes
1. **One-shot AI mode** — For Claude/ChatGPT/Codex. Runs a single command like `claude -p "message"`, captures stdout, displays it as a chat bubble. Each message is an independent process invocation.
2. **Persistent shell mode** — For plain terminal usage. Keeps a shell session alive, sends commands, captures output. Standard terminal behavior without the terminal chrome.

### Dock / Undock
- Works as a tab inside the main Cider panel (docked) OR as its own floating window (undocked).
- Shared ViewModel singleton (`AIChatViewModel.shared`) keeps state in sync — undocking doesn't lose your conversation.

### Process Management
- PATH resolution handles homebrew (`/opt/homebrew/bin`), nvm, npm global, cargo, plus login shell fallback via `$SHELL -l -c`.
- ANSI escape code stripping on all output so chat bubbles show clean text.
- Each AI model defines `printArgs` (e.g. `["--continue", "-p"]` for Claude) for one-shot invocation.

### Key Files

| File | Role |
|------|------|
| `Models/AIChatMessage.swift` | Message model (role, content, timestamp) |
| `Models/AIModelOption.swift` | Model definitions with CLI command and printArgs |
| `Services/AI/AIChatProcessService.swift` | Process management, PATH resolution, ANSI stripping |
| `ViewModels/AIChatViewModel.swift` | Shared singleton, message list, process lifecycle |
| `Views/AIChat/AIChatView.swift` | Main view — header + messages + input |
| `Views/AIChat/AIChatBubbleView.swift` | Chat bubble rendering |
| `Views/AIChat/AIChatInputView.swift` | Text input field |
| `App/AIChatPanel.swift` | Floating NSPanel for undocked mode |
| `Docs/TERMINAL.md` | Terminal/keyboard architecture doc |

---

## In Progress

### `--continue` Flag for Claude
Claude CLI supports `--continue` to resume the last conversation and `--resume <session-id>` to resume a specific one. Adding this so conversations aren't lost between messages.

### CLAUDE.md Vault Context
A `CLAUDE.md` file placed in the vault directory. Claude CLI auto-reads this file when invoked from that directory, giving it context about Cider, the vault structure, and the user's workspace — no manual prompting needed.

---

## Planned Features

### Conversation History
- Chat conversations saved as JSON files in the vault's `AI Chat/` folder.
- Each file stores: messages (role, content, timestamp), Claude session ID, model used, metadata.
- Filename convention: `2026-03-10_topic-slug.json`
- JSON format chosen over markdown — structured data with session IDs and timestamps makes resumption possible. Markdown export is a separate feature for sharing.

### Conversation Selector
- Slide-out panel or sidebar within the chat view.
- Shows past conversations: title, date, preview of first message.
- Click to load and resume. For Claude conversations, resumes via `--resume <session-id>`.
- Auto-titling based on first user message or AI-generated summary.

### Markdown Export
- Export any conversation as clean, readable markdown.
- Share-friendly format: headers for metadata, blockquotes or labels for role attribution.

### System Folder Migration
- Move `AI Chat/` into a hidden `.cider/` system folder: `~/CiderVault/.cider/AI Chat/`
- The `.cider/` directory would hold all Cider internal data (chat history, cache, configs) — hidden from the sidebar and Finder by default (dot-prefix)
- Currently handled by adding "AI Chat" to `reservedDirectoryNames` in `VaultFolderService.swift` — works but doesn't scale if more internal folders are added
- Migration: move existing `AI Chat/` contents into `.cider/AI Chat/`, update `AIChatViewModel.conversationsDirectory` path, and swap `reservedDirectoryNames` for a single `.cider` prefix check

### CLAUDE.md Auto-Generation
- Instead of a static context file, generate `CLAUDE.md` dynamically based on vault contents.
- Lists folder structure, file counts, recent activity — whatever helps the AI understand the workspace.

---

## Architecture Decisions

### One-shot mode, not interactive pipes
CLI tools like Claude and ChatGPT expect a TTY for interactive mode. Pipes break their interactive features (streaming, tool use confirmations). One-shot mode (`claude -p "message"`) works cleanly with `Foundation.Process` — send a message, capture stdout, done. Each invocation is stateless unless `--continue`/`--resume` is used.

### Shared singleton ViewModel
The chat needs to survive dock/undock transitions. `AIChatViewModel.shared` is a singleton that both the tab view and the floating panel read from. Originally tried passing it through `NSApp.delegate`, but `@NSApplicationDelegateAdaptor` cast fails at runtime. Singleton avoids the problem entirely.

### No SwiftTerm dependency
The original approach embedded a SwiftTerm terminal view. Removed it entirely in favor of pure SwiftUI + `Foundation.Process`. Benefits: no third-party dependency, full control over rendering, chat bubbles instead of terminal grid, easier to add features like conversation history and markdown rendering.

### JSON for history, markdown for export
Chat history is JSON — it needs session IDs, timestamps, role tags, and metadata to support resumption. Markdown is a lossy export format. Store as JSON, export as markdown when the user wants to share.

---

## Next Major Feature: Execution Modes

### The Problem
One-shot mode (`-p`) gives clean chat output but can't do multi-step tasks (sorting bookmarks, reorganizing files). Interactive mode can do everything but spams the chat with tool-use noise.

### Solution: Two Modes + CLAUDE.md Guardrails

**One-shot mode (default):**
- `-p` + `--dangerously-skip-permissions` — lets Claude read files and take actions
- `CLAUDE.md` in the vault enforces safe behavior: never delete without confirmation, summarize don't dump, plan before executing
- Clean chat bubble output — 90% of use cases
- User sees: question → clean response with a plan → approves → action on next message

**Interactive mode (advanced toggle):**
- Persistent process like Shell mode
- Full streaming output — tool calls, file reads, diffs, everything
- Power user mode for complex multi-step tasks
- Could parse Claude's structured output to show clean summaries and collapse noise (future polish)

**Mode selector:** Add a toggle in the model picker or a per-conversation setting. Default to one-shot.

### CLAUDE.md as the Control Layer
The vault's `CLAUDE.md` is auto-read by Claude CLI. It sets behavioral rules:
- Never modify/delete without listing the plan first
- Keep responses concise for chat bubbles
- Summarize data in plain language, don't dump JSON
- Break multi-step tasks into phases

This is better than code-level filtering because it's flexible, user-editable, and works across all conversations.

---

## Future Considerations

- **Streaming markdown rendering** — Render code blocks, bold, links, and other markdown in assistant bubbles instead of plain text.
- **Tool use visualization** — When Claude reads or edits files, show that activity in the chat (file names, diffs, status).
- **Cost tracking** — Track token usage or API cost per conversation. Claude CLI may expose this in stdout.
- **Additional CLI backends** — The model selector is extensible. Any CLI tool that accepts a prompt flag and returns text could be added.
- **Slash commands** — Considered and rejected. Native UI controls (pills, buttons, menus) are more discoverable and don't conflict with shell syntax. If the user types `/something` in shell mode, it should behave like a normal shell command, not a Cider action.
- **Custom agent support** — Let users add any CLI-based AI agent to the model picker. Since Cider doesn't bundle any CLIs — it just wraps whatever's installed — users should be able to add agents like Kimi K2, Aider, or any future tool. The "Add Custom Agent" flow would capture: name (pill label), command (CLI binary), icon (SF Symbol picker or default), and argument patterns (print args, continue args). This is essentially a user-editable version of `AIModelOption`. Custom agents would be stored in the vault config and appear alongside the built-in pills.
