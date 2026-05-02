# Computer Agent Chat App Concept

## One-Line Concept

A lightweight mobile and desktop chat client for talking to computer-based AI agents, with local-first session history, resumable chats, voice input, approvals, and provider-agnostic model/runtime support.

## Core Idea

Existing chat apps like Telegram, Discord, Slack, Signal, iMessage, ChatGPT, Claude, and Codex are not designed around the emerging use case of **controlling long-running agents on your own computer**.

They work as temporary transports, but they do not provide first-class concepts for:

- separate agent workspaces
- resumable local sessions
- per-session permissions
- computer/tool access approvals
- audit logs of actions performed on the machine
- voice capture tied to durable projects
- provider/model/runtime independence
- local ownership of chat history and artifacts

The proposed app is a thin, focused remote interface for computer agents. The heavy work happens on the user’s own Mac/PC/server. The phone or remote client is mostly a clean control surface.

## Not Tied to Cider

This concept does **not** need to be tied to Cider.

It could be a standalone app for anyone who wants to interact with agents running on their own computer, regardless of:

- LLM provider
- model vendor
- agent framework
- operating system
- local vs cloud model
- coding assistant choice

Cider could eventually integrate with or inspire this concept, but the broader product is:

> A universal chat and control client for personal computer agents.

## Provider-Agnostic Philosophy

The app should not be another single-provider AI chat app.

It should work with agents backed by:

- OpenAI
- Anthropic
- Gemini
- local LLMs
- OpenRouter
- Ollama
- LM Studio
- Hermes Agent
- Claude Code
- Codex
- OpenCode
- custom MCP-based agents
- future agent runtimes

The app owns the **conversation UX and session organization**, not the model.

The user should be able to swap models/runtimes without losing:

- chat history
- sessions
- project context
- files/artifacts
- permissions
- agent action logs

## Why Existing Apps Are Awkward

### Telegram

Good for mobile, voice notes, and remote access, but:

- DMs become one long thread
- topics require group setup
- sessions are not first-class
- permissions and approvals are bolted on
- chat history is not organized around local agent workspaces

### Discord / Slack

Better workspace/channel structure, but:

- built for communities/teams, not personal computer agents
- not local-first
- permissions are messaging permissions, not computer/tool permissions
- voice and mobile capture can be heavier than necessary

### iMessage / Signal

Good lightweight messaging, but:

- weak agent/bot primitives
- weak project/session organization
- limited structured control over tools/actions

### ChatGPT / Claude Apps

Good model UX, but:

- tied to a specific provider
- not primarily local-first
- not designed to control arbitrary computer agents
- chat history lives in vendor product surfaces
- limited durable integration with local files, repos, and vaults

## Target User

People who want to use AI agents as persistent collaborators on their own computers.

Examples:

- indie developers working across repos
- local-first/personal-knowledge users
- power users who want remote Mac/PC control
- people who brainstorm by voice while driving or walking
- users of multiple coding agents/providers
- users who want their chat history and agent logs stored locally

## Product Shape

### Thin Mobile Client

The mobile app does not need to run models or store everything locally.

It provides:

- chat UI
- voice recording
- session/workspace picker
- attachment uploads
- share sheet support
- push notifications
- approve/deny controls
- simple status indicators

### Agent Computer / Host

The user’s computer does the heavy work:

- runs agent runtime(s)
- stores sessions and logs
- stores files/artifacts
- manages model/provider credentials
- executes tools
- enforces permissions
- handles background jobs
- performs transcription/TTS if configured
- connects to local files, repos, and apps

## Core Features

### Cross-Transport Session Continuity

The same agent conversation should be resumable across communication surfaces. If a session starts in Telegram, Cider should eventually be able to open/resume that Hermes session directly instead of starting a separate disconnected chat.

Current Hermes reality: conversations are stored locally on the Mac under `~/.hermes/sessions/` and can be resumed by session ID/name through Hermes CLI/session APIs. Example from real use: the Telegram session titled `Media Preferences and Favorite` has ID `20260501_045533_cce0d1c1` and local files:

- `~/.hermes/sessions/session_20260501_045533_cce0d1c1.json`
- `~/.hermes/sessions/20260501_045533_cce0d1c1.jsonl`

Desired Cider behavior:

- show active/recent Hermes sessions inside Cider
- indicate transport/source: Telegram, Cider, CLI, cron, etc.
- resume a selected session through Hermes rather than rehydrating manually from transcript text
- preserve tool state, memory, title, workdir, loaded skills, and project/vault context where possible
- allow Cider to become another first-class client over the same local Hermes session store/API

Ownership distinction:

- Hermes owns the agent session internals: model conversation, tool context, memory injection, compression, run state, and Hermes session history.
- The shared Mac host owns multi-client coordination: client-facing chat IDs, mapping chat IDs to Hermes session IDs, send ordering, active-run locks, subscriptions, event fanout, attachments/status metadata, and permission/approval UX.
- Chost, Cider, Telegram, CLI, and mobile clients should not independently read/write Hermes session files as if they own them; they should send intents to the host, and the host should use supported Hermes resume/session interfaces or a dedicated Hermes adapter.
- The host should be installable/runnable independently of either app. Chost can bundle/start it for users who only want a better remote agent chat app. Cider can also bundle/start/connect to the same host for users who only want to talk to their vault from inside Cider. If both apps are installed, they should discover/connect to the same local host and share chats.
- Important product lesson: `resume Hermes session` is not the same thing as `join a live multi-client chat room`. Resuming or importing a Hermes session can give a client prior context, but it does not automatically broadcast new messages/responses to other transports. Live sync requires a host-owned chat/event stream that appends each turn once, runs one agent turn at a time, and broadcasts the resulting events to all subscribed clients.
- Important Hermes edge case: automatic context compression can split a gateway conversation into a new Hermes session ID while the user still experiences it as one Telegram thread. Example observed on 2026-05-01: `20260501_100416_ebff7f` split to `20260501_114444_443f9e` during compression. Chost/Cider must not assume one attached Hermes session ID is permanent for the visible chat. The host/adapter should detect session-split events, update the client-facing chat → current Hermes session mapping, preserve a lineage/alias list of prior session IDs, and notify attached clients to follow the new active session without losing history.
- Integration maturity levels:
  1. **Resume session:** a client can send a turn to an existing Hermes session ID. This gives continuity of agent context, but does not make every UI show every message.
  2. **Sync from Hermes session:** a client imports/polls Hermes session history into its own chat view, de-duplicates messages, preserves ordering, and labels imported entries by source. This lets Chost show Telegram-origin conversation history without yet making Telegram a live subscribed room.
  3. **True shared room:** the local host owns a client-facing chat/event stream and all clients/transports subscribe. User messages, assistant responses, tool events, approvals, attachments, and run status are broadcast to Chost, Cider, Telegram, mobile, etc. as appropriate.
- Telegram-specific caveat: Telegram will only display messages that are sent through the Telegram bot/API. If Chost appends to Hermes history, Telegram will not automatically re-render that notebook entry; the host must explicitly bridge/broadcast to Telegram if the user wants it visible there.

Packaging direction:

- Shared local service: `Agent Host` / `Local Agent Host` as the neutral backend.
- Chost: standalone chat client that can install or manage the host for remote/mobile agent chat.
- Cider: vault-native client that can install or manage the host for in-app AI/vault conversation.
- Hermes: first runtime adapter behind the host, not the only possible runtime forever.

Product distinction: Telegram/Cider/CLI/Chost are clients or transports. The durable agent context should remain on the Mac in Hermes-owned session storage where possible, while Cider/Chost provide synchronized client surfaces over a host-managed mapping layer. Avoid duplicating Hermes history unless needed for indexing/cache; if mirrored, treat Hermes as source of truth for agent-session semantics.

### 1. Workspaces

Users can create workspaces such as:

- Cider Vault
- Cider Codebase
- Mac Ops
- App Ideas
- Marketing
- Personal Planning
- Specific software repos

Each workspace can have its own defaults:

- allowed folders/repos
- default tools
- memory scope
- permission profile
- preferred model/runtime
- checkpoint rules

### 2. Agent Sessions / Threads

Each chat thread maps to an actual agent session.

Sessions are:

- named
- resumable
- searchable
- exportable
- locally stored
- associated with files, repos, or vault paths
- optionally connected to a specific agent runtime/model

Example sessions:

- `Cider Vault Agent`
- `Cider CLI Batch Save Plan`
- `Mac Downloads Cleanup`
- `App Ideas - Driving Notes`
- `Marketing Launch Copy`

### 3. Local Chat History

Chat history should be stored on the user’s computer, not trapped inside a provider app.

The user should be able to:

- search past chats
- resume old sessions
- export conversations
- link chats to files/projects
- archive or delete sessions
- create durable summaries/checkpoints

### 4. Voice-First Ideation

The app should support lightweight voice use:

- hold-to-talk voice notes
- automatic transcription
- optional spoken replies
- driving/walking brainstorm mode
- turn voice rambles into notes, tasks, or plans

Voice should be tied to the selected workspace/session so ideas do not get lost in a generic chat history.

### 5. Permission Modes

Agent control needs clear permission modes, such as:

- Chat only
- Read-only
- Plan only
- Docs only
- Safe edits
- Code edits
- Vault mutations
- System-wide operations
- Ask before destructive actions
- Autonomous for a bounded time

Permissions should be visible in the UI and attached to the active session/workspace.

### 6. Approvals

When an agent wants to perform sensitive actions, the app should provide native approval flows:

- approve
- deny
- modify request
- approve once
- approve for this session
- approve for this workspace

Approval cards should show:

- command/action
- target files/folders
- expected effect
- risk level
- rollback/checkpoint availability

### 7. Action Logs

Users need to know what the agent did.

The app should keep structured logs of:

- tool calls
- shell commands
- file writes
- file moves/deletes
- network requests when relevant
- messages sent
- background jobs
- approvals/denials

This turns the app from “mystery chatbot” into an auditable computer-agent console.

### 8. Checkpoints

The app should make checkpointing first-class.

A checkpoint can promote transient chat content into durable artifacts:

- memory
- notes
- docs
- issues
- plans
- tasks
- Codex/Claude prompts
- project decisions
- regression cases

Users should be able to say:

> checkpoint this

and the agent/app should preserve the important parts in the right place.

### 9. Attachments and Share Sheet

Mobile users should be able to share into any workspace/session:

- URLs
- screenshots
- PDFs
- images
- videos
- voice notes
- text snippets

The app should ask or infer where the item belongs, then hand it to the host agent for processing.

### 10. Background Work

Agents often work while the user is away.

The app should support:

- background task status
- progress notifications
- completion summaries
- “continue working” controls
- scheduled jobs
- reconnecting to long-running sessions

## Architecture Sketch

```text
Mobile App / Web App
  - chat UI
  - voice capture
  - approvals
  - notifications
  - session picker
        |
        v
Secure Relay / Direct Connection
        |
        v
Agent Host on User Computer
  - session store
  - agent runtime adapter
  - permission manager
  - tool/action engine
  - audit log
  - file/repo/vault access
        |
        v
Model / Agent Runtime Layer
  - Hermes
  - Codex
  - Claude Code
  - local LLMs
  - MCP agents
  - custom runtimes
```

## Key Design Principle

The mobile app should not own the intelligence or the user’s data.

It should be a trusted remote control for the user’s own agent host.

The durable system of record is the user’s computer:

- sessions
- logs
- files
- memories
- artifacts
- credentials
- permissions

## Possible Tech Stack

The stack should optimize for three things:

1. fast MVP development
2. secure remote access to a user-owned computer agent
3. long-term provider/runtime independence

The app should avoid putting core chat history, permissions, or agent state exclusively inside a hosted SaaS backend. A hosted backend may be useful as a relay, but the agent host should remain the system of record.

### Recommended MVP Stack

Best near-term route:

- **iOS client:** SwiftUI
- **Mac host app/service:** Swift + SwiftUI/AppKit, or a lightweight Node/Python daemon if integrating with existing agent tooling is easier
- **Local host database:** SQLite
- **Sync/relay:** Convex, Supabase Realtime, or a small custom WebSocket relay
- **Push notifications:** APNs through the relay
- **Voice transcription:** host-side Whisper/faster-whisper first, with optional hosted providers
- **TTS:** host-side or provider-backed TTS, optional for MVP
- **Agent adapter:** start with Hermes Agent, but define a small runtime protocol so other agents can be added later

This gives a polished native iOS experience while keeping the durable state on the agent computer.

### Why SwiftUI for iOS

SwiftUI is the best first choice if the initial product is iPhone-first:

- native voice recording and playback
- native push notification handling
- native Share Sheet support
- Face ID / Keychain pairing storage
- good background/mobile UX
- best fit for a personal remote-control app

A web app could come later, but mobile ergonomics matter a lot for driving/walking voice capture.

### Host App / Agent Service

The host should run on the user’s Mac/PC and expose a small authenticated API to the mobile client/relay.

Responsibilities:

- store sessions, messages, logs, checkpoints, and workspace config
- launch/connect to agent runtimes
- enforce permissions
- execute tools through the agent runtime
- handle file/repo/vault access
- stream agent responses
- create approval requests
- send notification events

Implementation options:

1. **Swift Mac host**
   - best if targeting Apple users first
   - integrates well with Keychain, LaunchAgent, file permissions, local notifications, and Cider
   - more work if integrating many non-Swift agent runtimes

2. **Node/TypeScript host daemon**
   - best for cross-platform and web/agent ecosystem integration
   - easy WebSocket/SSE APIs
   - easy package/runtime integration
   - good match for provider-neutral agent adapters

3. **Python host daemon**
   - best for ML/local-model tooling and quick automation
   - easy file/system scripting
   - less polished for native Mac service UX

Pragmatic MVP choice: use the stack that most directly wraps the first supported agent runtime. If Hermes is first, a Python/TypeScript host adapter may be fastest. If a Cider-native Mac app is first, Swift host integration may be better.

### Local Database

Use SQLite on the host for the durable source of truth.

Store:

- workspaces
- sessions
- messages
- attachments metadata
- action logs
- approvals
- permission profiles
- runtime configs
- checkpoints
- notification delivery state

SQLite is simple, inspectable, portable, and local-first. It also makes export/backup straightforward.

### Storage and Transport Model

The app does not need a traditional cloud database as the authoritative store.

There are three separate concerns that should not be conflated:

1. **Durable storage** — where chats, sessions, logs, permissions, approvals, attachments, and artifacts live.
2. **Transport** — how a mobile device sends messages to the agent host and receives responses.
3. **Notification wakeup** — how the user is alerted when the host needs attention or finishes work.

Recommended principle:

> Store durable data on the user’s devices, especially the agent host. Use cloud services only for transport, wakeup, or optional backup/sync.

The cleanest local-first model:

- the Mac/PC agent host owns the canonical database
- the phone may keep an encrypted local cache for offline reading/search
- the relay, if used, only sees encrypted envelopes and routing metadata
- no chat content, tool results, calendar/email data, or file snippets need to be stored permanently in the cloud

So yes: a message could pass through Convex or another relay while the actual content remains encrypted and is only stored on the user’s devices.

### Does It Need a Database?

It needs a structured store somewhere, but that does not have to mean a cloud database.

Best answer:

- **Host machine:** yes, use a local database such as SQLite.
- **Mobile device:** optionally use a local encrypted cache, likely SQLite/Core Data/SwiftData.
- **Cloud relay:** should not be the source of truth; it can be ephemeral or store only encrypted queued messages.

A file-only approach is possible for prototypes, but a database becomes useful quickly for:

- sessions
- messages
- message delivery state
- search
- attachments metadata
- action logs
- approvals
- workspace permissions
- background job status
- sync cursors
- device identities

SQLite is a good fit because it is local, portable, inspectable, and durable without requiring a hosted backend.

### Transport Options

The app needs a way for the phone to reach the user’s computer while away from home. There are several viable routes.

#### Option 1: Direct Device-to-Host Connection

The ideal privacy model is direct communication between the mobile app and the agent host.

Possible approaches:

- Tailscale / WireGuard private network
- local network discovery when at home
- Cloudflare Tunnel
- reverse SSH tunnel
- user-hosted relay
- direct WebRTC/WebSocket connection with NAT traversal

Benefits:

- no SaaS relay required for message transport
- less metadata leakage
- simpler privacy story
- host remains clearly authoritative

Tradeoffs:

- harder onboarding for normal users
- NAT/firewall issues
- mobile background connectivity can be tricky
- push notifications still usually require APNs or a notification relay

Best for: power users, privacy-focused users, self-hosters, local-first enthusiasts.

#### Option 2: Hosted Relay With E2EE

This is likely the best consumer MVP.

A service like Convex, Supabase Realtime, or a custom relay can pass encrypted messages between phone and host without being able to read them.

Relay stores only:

- encrypted message envelopes
- delivery queues
- host/device presence
- coarse routing metadata
- push-notification triggers

Relay does **not** store readable:

- chat contents
- attachments
- transcripts
- tool outputs
- approval details
- email/calendar/file contents
- provider credentials

Benefits:

- easiest mobile experience
- works away from home
- supports offline host queueing
- enables push notifications
- fastest MVP if using Convex or similar

Tradeoffs:

- some metadata still exists in the relay
- requires strong E2EE implementation
- users must trust that the client/host encryption is implemented correctly

Best for: mainstream MVP.

#### Option 3: Hybrid Relay + Direct Mode

Best long-term architecture:

- default to hosted relay with E2EE for easy onboarding
- allow direct LAN/Tailscale/self-hosted relay modes for advanced users
- keep the same app/session model regardless of transport

This lets the product be easy for normal users without locking privacy-focused users into a cloud relay.

#### Option 4: Cloud Database As Source of Truth

This is the least aligned with the product thesis.

A hosted database could store sessions/messages directly, but then the product becomes much closer to a normal SaaS chat app. That weakens the local-first promise and increases risk for sensitive integrations.

Use only if the product deliberately chooses convenience over local-first privacy.

### Relay / Sync Options

If a hosted relay is used, the app needs a way for the phone to reach the user’s computer while away from home. There are three viable hosted routes.

#### Option A: Convex Relay

Convex could be a strong MVP relay layer for:

- realtime message sync
- presence/status
- queued outbound messages
- push notification triggers
- lightweight cloud functions
- fast iteration

But Convex should not be the sole durable source of truth for private agent sessions if the product promise is local-first. Treat it as a relay/cache/control plane:

- mobile writes message intent to Convex
- host agent receives it, stores it locally, processes it
- host streams status/results back through Convex
- host remains authoritative

Best for: fast MVP, realtime UX, less backend plumbing.

Risk: product becomes less clearly local-first if too much data lives in Convex.

#### Option B: Supabase Realtime Relay

Supabase is a reasonable alternative if Postgres, auth, storage, and realtime are desired.

Best for:

- standard SQL backend
- auth/users/teams later
- attachment/object storage
- hosted dashboard/ops

Risk: heavier than needed for a personal-agent relay and easier to drift toward cloud-owned history.

#### Option C: Custom Relay

A small custom WebSocket/SSE relay can be purpose-built:

- device pairing
- encrypted envelopes
- message queueing
- push notification fanout
- host online/offline state

Best for: control, privacy, minimal long-term dependency.

Risk: slower MVP; more security and infrastructure work.

### Direct Connection Alternatives

For local/network power users, support direct connection modes later:

- Tailscale / WireGuard
- local network discovery
- reverse SSH tunnel
- Cloudflare Tunnel
- custom self-hosted relay

These can reduce cloud dependency, but they are too much setup for a simple consumer MVP.

### Authentication, Pairing, and E2EE

Pairing should feel like connecting a watch or authenticator app, but the security model needs to be stronger than a normal chat app because the agent may be connected to sensitive local data and integrations such as calendar, email, files, contacts, reminders, browser sessions, code repos, and credentials.

End-to-end encryption should be a core product requirement, not a later premium feature.

Possible pairing flow:

1. host app shows QR code
2. iOS app scans QR code
3. devices exchange public keys
4. host stores mobile device identity
5. mobile stores host identity in Keychain
6. relay only sees encrypted envelopes or minimal routing metadata where possible
7. host can revoke a paired device at any time

Security goals:

- chats, attachments, approval payloads, and action results should be E2EE between the mobile client and the agent host whenever a relay is used
- the relay should not be able to read message contents, attachments, transcripts, approval details, tool results, calendar/email content, or file snippets
- the relay should not hold model/provider credentials
- the relay should not be able to execute tools
- the relay should not be the durable source of truth for private agent sessions
- the host must approve paired devices
- lost devices can be revoked from the host
- sensitive actions still require permission checks
- calendar, email, contacts, and file-system integrations should be treated as high-sensitivity scopes
- notification pushes should avoid leaking sensitive content; default to generic notifications like “Agent needs approval” or “Task complete” unless the user opts into previews

Recommended encryption shape:

- each paired device has a long-term identity key
- each host has a long-term identity key
- sessions use forward-secure message keys where practical
- attachment blobs are encrypted client-side/host-side before touching the relay
- approval cards are encrypted just like chat messages because they may reveal file paths, email subjects, calendar events, shell commands, or private data
- local keys live in Keychain/Secure Enclave where available
- recovery/re-pairing should prefer explicit host approval over cloud account recovery

The relay may still provide:

- routing
- encrypted message queueing
- host online/offline state
- push-notification fanout
- coarse delivery receipts

But the relay should not become a privacy boundary the user has to trust with content.

### Sensitive Integration Scopes

Because this app may connect agents to the user’s real computer, permissions should distinguish normal chat from sensitive integrations.

High-sensitivity scopes include:

- email read/search/send
- calendar read/write
- contacts
- reminders/tasks
- files outside explicitly allowed folders
- shell/terminal commands
- browser/session data
- password managers or credential stores
- messaging apps
- financial/medical/legal documents

The app should support per-workspace and per-session scopes such as:

- “chat only”
- “read calendar, ask before writing”
- “read email metadata only”
- “draft email but ask before sending”
- “read this repo only”
- “vault-safe mutations only”
- “ask before shell commands”
- “no secrets/credentials access”

Every sensitive tool call should be logged locally with:

- timestamp
- requesting session
- tool/action name
- target resource
- approval decision if any
- summarized result
- redaction of secrets where possible

### Runtime Adapter Interface

Define a small abstraction so the app is not tied to one LLM provider or agent framework.

A runtime adapter should support:

- `sendMessage(sessionID, message)`
- `streamEvents(sessionID)`
- `cancel(sessionID)`
- `listSessions()`
- `resumeSession(sessionID)`
- `listTools()`
- `requestApproval(action)`
- `applyApproval(approvalID, decision)`
- `getArtifacts(sessionID)`

Start with one adapter, but design the shape so Hermes, Codex, Claude Code, OpenCode, local agents, or MCP runtimes can fit behind it.

### Attachments and Voice Pipeline

For attachments:

- mobile uploads encrypted attachment to relay or directly to host when reachable
- host stores canonical copy locally
- message stores only metadata and local file reference
- agent decides how to process/import based on workspace permissions

For voice:

- mobile records compressed audio
- host transcribes if online
- fallback cloud transcription can be optional
- transcript is stored with the session
- original audio can be retained or discarded based on user setting

### Recommended First Build

Most pragmatic first build:

1. Native iOS app in SwiftUI.
2. Mac host daemon/app that stores SQLite sessions locally.
3. Convex as realtime relay/control plane, not source of truth.
4. Hermes Agent runtime adapter first.
5. APNs for notifications.
6. Voice note capture with host-side transcription where possible.
7. Basic permission profiles and approval cards.

This route minimizes frontend/backend yak shaving while preserving the important product principle: the user’s computer owns the real agent state.

### Long-Term Architecture

Long term, the app should support pluggable relay modes:

- hosted relay for easy onboarding
- self-hosted relay for privacy/power users
- direct Tailscale/WireGuard mode
- local-network-only mode

It should also support multiple host machines:

- MacBook
- desktop PC
- home server
- work machine

Each host can advertise available workspaces, runtimes, and permission profiles.

## MVP Scope

A realistic MVP could include:

- Mac host app/service
- iOS client
- secure pairing
- session list
- chat screen
- voice note transcription
- text replies
- push notifications
- basic approval cards
- local session storage
- runtime adapter for one agent framework first, but designed for many

The MVP does not need:

- complex team collaboration
- full cloud sync
- built-in model hosting
- heavy document editing
- social/community features

## Differentiation

This is not a ChatGPT clone.

It is:

- local-first
- provider-agnostic
- agent-runtime-agnostic
- workspace/session-oriented
- permission-aware
- action-auditable
- voice-friendly
- built for computer control, not just Q&A

## Possible Taglines

- “A command center for the agents running on your computer.”
- “Chat with your computer agents from anywhere.”
- “Local-first chat history for AI agents.”
- “One app for every agent, model, repo, and workspace.”
- “Remote control for your personal AI workforce.”

## Relationship to Cider

Cider can use this idea in two possible ways:

1. **Standalone product inspiration**
   - A separate app that works with any agent host.

2. **Cider-integrated future**
   - Cider becomes one workspace/provider inside the agent chat system.
   - Cider’s vault becomes a durable memory/artifact layer for agent sessions.
   - Cider’s local-first philosophy and vault structure inform the product design.

Either way, this idea reinforces a broader direction:

> Users need a local-first, provider-neutral way to talk to and control their computer agents from anywhere.

## Open Questions

- Should the first version be iOS-only, web-first, or cross-platform?
- Should it connect directly to the host computer or use a lightweight relay?
- How should pairing/authentication work?
- Should the app store any history locally on mobile, or only cache host-owned data?
- What is the safest permission model for system-wide actions?
- How should it support multiple agent frameworks without becoming too abstract?
- Is the best first customer developers, local-first enthusiasts, or general AI power users?
- Should this be part of Cider eventually, or remain separate?
