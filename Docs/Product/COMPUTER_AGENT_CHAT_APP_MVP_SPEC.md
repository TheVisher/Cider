# Computer Agent Chat App MVP Spec

## Product Direction

This app is a private, organized chat client for agents running on the user's own computer.

The first product promise is simple:

> Talk to the AI agent on your Mac from your phone, with separate chats instead of one endless Telegram thread.

The product is not primarily a coding agent interface. Coding is one possible use case. The broader purpose is to turn local agents such as Hermes, OpenClaw, or future custom agents into a familiar multi-chat experience similar to iMessage, Telegram, ChatGPT, or Claude, while keeping the agent runtime and durable history anchored to the user's own machine.

## Core User Experience

The app should feel like a normal chat app:

- a list of chats
- a new chat button
- a single active chat window
- message bubbles
- text input
- later voice input, attachments, approvals, and workspaces

The agent-specific complexity should stay mostly invisible until needed. Users should not feel like they are operating a server console.

## Finished App Goals

Long term, the app should support:

- iPhone-to-Mac and Mac-to-Mac chat with local agents
- multiple organized chats, each with its own durable history
- true runtime-backed agent sessions when the runtime supports them
- workspaces or categories such as General, Receipts, App Ideas, Code Repos, and Personal Planning
- Hermes first, then OpenClaw and custom connectors
- optional import/linking of existing runtime sessions from local stores such as Hermes's `~/.hermes/state.db`
- direct or private network connectivity where possible
- Tailscale/WireGuard/manual host address support for early remote use
- app-level encryption after the basic connection loop works
- voice capture and spoken replies after text sessions work
- approval cards and action logs after core chat is reliable
- multiple Mac/host support later

## Key Product Decisions

### Chats Map to Real Agent Sessions

One app chat should map to one real runtime session when possible.

For Hermes, this means the app should create, list, and resume actual Hermes sessions rather than stuffing all user messages into one global conversation. This avoids the Telegram problem where everything becomes one long context.

The app should store a mapping like:

```text
AppChat
- id
- title
- workspace_id
- runtime_id
- runtime_session_id
- created_at
- updated_at
```

If a future runtime cannot create/resume isolated sessions, its connector should be considered incomplete or degraded.

### Mac Is the Source of Truth

The Mac host owns the durable state.

The iPhone is initially a remote client. It may later maintain a local cache for speed and offline reading, but the first version should treat the Mac database as authoritative.

### Agnostic Runtime Architecture

The app should not become a Hermes-only product.

It should have an internal connector model:

```text
Host
  -> Runtime Connector
      -> Runtime Session
          -> App Chat
```

The first visible connector is Hermes. The UI can hide connector management at first, but the data model should not assume Hermes forever.

### Prototype First, Native Path Preserved

The ideal finished app may be native Swift/SwiftUI on iPhone and Mac, especially for Apple-only use. However, the first foundation should optimize for testing the hardest unknowns:

- direct Mac-hosted communication
- organized sessions
- persistence
- iPhone-to-Mac access over LAN/Tailscale
- Hermes integration feasibility

The prototype should use a small, language-agnostic API so the backend can later be reimplemented inside a native Swift Mac app without changing the client contract.

## MVP Foundation

The first milestone should prove organized multi-chat text sessions from a phone/browser to a Mac-hosted agent service.

### Included

- Mac local host service
- SQLite app database
- simple chat list
- new chat
- open chat
- send message
- receive mock agent reply
- message history persisted on the Mac
- simple browser-based test client
- LAN access
- Tailscale/manual host address access from iPhone browser
- internal runtime connector interface
- mock runtime connector
- Hermes connector investigation after the mock flow works

### Deferred

- polished native iPhone app
- polished native Mac app
- voice input/output
- app-level end-to-end encryption
- APNs/push notifications
- CloudKit
- custom NAT traversal
- workspaces UI
- multiple hosts
- multiple runtime connector UI
- approval cards
- action logs
- attachment processing
- importing existing Hermes sessions

## Initial Architecture

```text
Browser / iPhone Test Client
  - chat list
  - chat screen
  - new chat
  - message input
        |
        v
Mac Host Service
  - local HTTP API
  - optional event stream later
  - device/test auth token
  - SQLite app DB
  - chat/session metadata
  - message persistence
  - runtime connector interface
        |
        v
Runtime Connector
  - MockAgent first
  - Hermes next
  - OpenClaw later
```

## API Contract

The first API should stay small and portable:

```text
GET  /health
GET  /chats
POST /chats
GET  /chats/:id
GET  /chats/:id/messages
POST /chats/:id/messages
```

Later additions:

```text
GET  /events
POST /pair
GET  /runtimes
POST /runtimes
POST /approvals/:id/decision
```

The protocol should eventually support event-style responses:

```text
user_message
assistant_started
assistant_delta
assistant_message
tool_event
approval_request
approval_decision
session_updated
error
```

The MVP can implement only complete assistant messages.

## Database Shape

The app should own its own SQLite database for product metadata and message persistence.

Initial tables:

- `chats`
- `messages`
- `runtimes`

Future tables:

- `workspaces`
- `hosts`
- `paired_devices`
- `approvals`
- `action_logs`
- `attachments`

The Hermes connector may read Hermes's session database for import/listing later, but the app should not use Hermes's database as its own product database.

## Connectivity Strategy

The first foundation should use a direct host address:

- local LAN IP for initial testing
- Tailscale IP or MagicDNS name for away-from-home testing

This avoids Convex, Supabase, or a custom relay during the first proof of concept.

Security sequence:

1. Basic local/Tailscale connectivity
2. Auth token or pairing token
3. TLS/HTTPS if practical
4. App-level encryption later

The first goal is to prove that the phone can reach the Mac and use organized chat sessions. Stronger encryption is required before real private use, but it should not block the earliest architecture test.

## Hermes Integration Plan

Hermes is the first real runtime target.

Known from documentation:

- Hermes stores conversations as sessions.
- Sessions can be listed, named, resumed, exported, and searched.
- Session metadata lives in `~/.hermes/state.db`.
- Raw transcripts live in `~/.hermes/sessions/`.
- Hermes supports multiple platform sources, including Telegram, CLI, webhook, API server, and others.

Investigation tasks:

- determine the cleanest way to create a new Hermes session programmatically
- determine how to send a message into a specific resumed session
- determine whether Hermes exposes a local API server suitable for this app
- determine whether streaming is available
- determine whether approval requests can be surfaced through an adapter
- determine how existing Telegram sessions can later be imported or linked

The MVP should not depend on Hermes until the mock agent flow works.

## Success Criteria

The foundation is successful when:

1. The Mac host service runs locally.
2. A browser client can create multiple chats.
3. Each chat has separate message history.
4. Messages persist in SQLite on the Mac.
5. The same client can connect from iPhone over LAN or Tailscale.
6. The runtime connector boundary is clear enough to add Hermes next.

After that, the next milestone is a Hermes connector that maps each app chat to a true Hermes session.

