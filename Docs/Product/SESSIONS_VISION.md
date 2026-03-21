# Sessions Tab Vision

## Overview

A Sessions tab in Cider that lets you spawn, manage, and chat with Claude Code agents — all from within the app. No terminal needed. Sessions run as background processes on your Mac, with a chat UI rendered as dynamic masonry cards. Remote access via Convex lets you control sessions from web or iOS.

## Core Concept

Replace the "build a CLI terminal" idea with a dashboard that controls Claude Code sessions. You're not doing anything technical in a terminal — you're sending messages to agents. A visual dashboard with chat cards is the right interface for that.

## Architecture

### Local (macOS)

- **Process management** — `Process()` spawns `claude` as a child process of Cider. No terminal emulator, no SwiftTerm, no PTY. Just `Process` + `Pipe` on stdin/stdout.
- **Structured output** — `claude --output-format stream-json` gives structured JSON events for messages, tool calls, tool results, permission prompts, errors.
- **Session lifecycle** — create, pause, resume, kill sessions from the UI. Each session is a managed `Process` instance.
- **Project folder** — each session can target a specific project directory (`process.currentDirectoryURL`). Claude Code auto-loads that project's CLAUDE.md.

### Remote (Convex)

- **Real-time relay** — session state (messages, status, tool calls) synced to Convex documents.
- **Bidirectional** — send messages from web/iOS → Convex mutation → local bridge picks it up → pipes to Claude Code stdin.
- **Output capture** — local bridge reads Claude Code stdout → pushes to Convex → web/iOS subscribes and renders live.
- **Same infra** — reuses existing Convex deployment, auth, and device verification from bookmark sync.

### Security

- **Auth gating** — Convex auth (already wired up). Only your authenticated account can read/write session documents.
- **Device verification** — local bridge registers with a device ID (like ConnectedDevices). New devices need approval.
- **Message signing** — messages sent via Convex are signed; local bridge verifies before piping to stdin.
- **Input sanitization** — bridge validates incoming messages. No control characters, no shell escapes. Just plain text to Claude Code.
- **Permission prompts stay interactive** — destructive action approvals render as Approve/Deny buttons in the UI. No auto-approving from remote.
- **Convex built-in protections** — TLS transport, row-level security, server-side validation, no direct DB access, mutation rate limiting.

## Sessions Tab UI

### Dynamic Masonry Layout

Cards resize based on status and focus:

- **Idle session** → compact card (title, status dot, last message preview, project name)
- **Active session** → medium card (title, current task, streaming output preview, progress indicators)
- **Focused session** → expanded card (full chat history, input field, tool call details visible)
- Click a card → it expands, others compress to make room
- The layout breathes with activity — active sessions naturally take more space

### Card Contents

Each session card shows:
- Session title / project name
- Status badge (idle, working, waiting for approval)
- Last message or current task description
- Tool call activity (collapsed: "Edited 3 files", expanded: inline diffs)
- Chat input field (when focused/expanded)
- Action buttons: pin to AI panel, kill, restart, settings

### Session Creation

"+ New Session" button opens a picker:
1. **Recent projects** — auto-discovered directories with `.git`, `package.json`, `CLAUDE.md` in common locations
2. **Open folder** — native macOS `NSOpenPanel` folder picker
3. **Pinned projects** — starred folders that always appear
4. **Blank session** — no project context, general purpose

Preset templates possible:
- "New Session (Cider repo)" → `claude --project ~/Cider`
- "New Session (Research)" → starts with a research-focused system prompt

### Slash Commands & Skills

All Claude Code slash commands work — typed in the chat input, piped to stdin:
- `/commit`, `/review`, custom skills — all handled by Claude Code
- Autocomplete for `/` commands in the input field
- Tool calls rendered as collapsible cards (file reads, edits, bash output)
- Permission prompts rendered as Approve/Deny buttons
- Cider-specific toolbar shortcuts (e.g., "Commit" button that sends `/commit`)

## AI Panel Integration (Option+A)

### Pop-out to AI Panel

Each session card has a "pin to AI panel" button. Click it and that session becomes the one behind Option+A.

**Flow:**
1. Sessions tab → see your active sessions
2. Click pin button on "Trip Research" session
3. Navigate to your Trip Ideas folder
4. Option+A → Claude is right there, with full trip research context
5. "Find me Airbnbs near the places we bookmarked" → it sees your folder items
6. Switch sessions anytime — pin a different card

### Provider Architecture

The existing `AIAssistantProvider` protocol abstracts the model backend. Add a third provider:

```
FoundationModelsProvider  — Apple Intelligence (free, limited)
MLXProvider               — Qwen 2.5 via MLX (local, free, good for quick tasks)
ClaudeCodeProvider        — Claude Code session (full power, subscription)
```

The `ClaudeCodeProvider` connects to a managed `Process` instance. When pinned to the AI panel, the chat UI routes through this provider instead of MLX.

**Benefits over MLX for complex tasks:**
- Full Claude model (not a small local model)
- All 23 Cider tools work through Claude Code's native tool system
- Persistent context across conversation (same session)
- Can read/write files, run commands, commit code

### Context Awareness

When pinned to the AI panel, the Claude session has access to:
- Current item you're viewing (bookmark, note, folder) via Cider's context injection
- All 23 AI tools (bookmarks, notes, folders, kanban, contacts, events, todos, sessions, tags, labels)
- The full project context if the session targets the Cider repo

**Use cases:**
- Writing a note → Claude helps draft, research, format
- Browsing bookmarks → Claude summarizes, finds related items, suggests tags
- Kanban board → Claude creates/moves cards based on conversation
- Trip planning folder → Claude researches destinations, creates bookmarks for hotels/flights, adds notes with itineraries

## Cross-Platform Views

### Desktop (Cider macOS)
- Full Sessions tab with masonry layout
- Session creation (spawn processes locally)
- Pin to AI panel (Option+A)
- Direct process management

### Web (Cider Web)
- Sessions tab showing active sessions on your Mac
- Chat UI for each session (relay via Convex)
- Cannot create new sessions (no local process access)
- Read/write messages, approve permissions remotely

### iOS (Cider iOS)
- Same as web — view and chat with active sessions
- Push notifications for permission prompts or session completion
- Cannot spawn new sessions (relay only)

## Requirements

### User Requirements
- Claude Code installed on their Mac (`claude` binary in PATH)
- Active Claude subscription (for the API usage)
- Cider account with Convex sync enabled (for remote access)

### Onboarding
- If `claude` binary not found → show install card with link
- If no subscription → explain this uses their Claude account
- First session → guided walkthrough of the card UI

## Implementation Phases

### Phase 1 — Local Session Management
- Spawn/kill `Process` instances running `claude --output-format stream-json`
- Parse structured JSON output into chat messages
- Render in a basic list/card view in a new Sessions tab
- Chat input that pipes to stdin
- Permission prompt buttons (approve/deny)

### Phase 2 — Masonry Layout & Polish
- Dynamic card sizing based on status/focus
- Tool call rendering (collapsible cards, inline diffs, code blocks)
- Slash command autocomplete
- Project folder picker with recent/pinned projects
- Session persistence across app restarts

### Phase 3 — AI Panel Integration
- `ClaudeCodeProvider` conforming to `AIAssistantProvider`
- Pin-to-panel button on session cards
- Context injection (current item) when pinned
- Mode switcher in AI panel (MLX vs Claude session)

### Phase 4 — Remote Access via Convex
- Bridge service pushing session state to Convex
- Web/iOS views subscribing to session documents
- Remote message sending (Convex mutation → local bridge → stdin)
- Device verification and message signing
- Remote permission approval

## What NOT to Build

- **Terminal emulator** — no SwiftTerm, no PTY, no terminal rendering. Just Process + pipes + chat UI.
- **Custom AI backend** — Claude Code handles all the AI. We're just a UI layer.
- **Session transfer between machines** — sessions are tied to the Mac running them. Remote access is relay, not migration.
- **Multi-user sessions** — one user per session. This isn't a collaboration tool.

## Open Questions

1. Should sessions auto-start on app launch, or always manual?
2. How to handle Claude Code updates — does Cider check for CLI version?
3. Should we support other CLI agents (Cursor agent, Codex) via the same card system?
4. How many concurrent sessions is reasonable before performance degrades?
5. Should the local bridge be a LaunchAgent (always running) or only active when Cider is open?
