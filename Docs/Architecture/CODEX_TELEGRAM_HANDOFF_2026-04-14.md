# Codex Telegram Handoff: Persistent Runtime + Vault Count Routing

> Status: historical handoff/checkpoint. Current durable Main Brain and Hermes integration guidance lives in `Docs/Features/MainBrain/`.

## Purpose

This handoff captures the current state of the Telegram-backed Codex runtime in Cider, what has already been fixed, what is still not wired, and the recommended next step.

Use this when resuming in a new conversation so the next agent does not have to reconstruct the work from logs.

Read together with:

- [CODEX_HANDOFF_2026-04-14.md](/Users/minivish/Cider/Docs/Architecture/CODEX_HANDOFF_2026-04-14.md)
- [AGENT_SERVICE.md](/Users/minivish/Cider/Docs/Architecture/AGENT_SERVICE.md)
- [MANAGED_AGENT_RUNTIME.md](/Users/minivish/Cider/Docs/Architecture/MANAGED_AGENT_RUNTIME.md)

---

## Executive Summary

The current Telegram -> Codex CLI runtime path is working.

What is now working:

- Telegram can route messages into a persistent Codex process runtime
- Codex startup / initialize / thread-start succeeds reliably
- Telegram receives final responses instead of timing out on normal turns
- Codex can answer vault questions by using the mounted vault plus `cider-cli`
- high-level count questions are now explicitly routed toward `cider-cli status --json`

What is not yet wired:

- Codex process runtime does **not** directly call Cider app tools from `AgentToolRegistry`
- `supportsToolCalling` for `CodexProcessRuntime` is still `false`
- Codex is succeeding through prompt-guided shell + CLI usage, not native app-side tool calls

Current pragmatic recommendation:

1. keep using `cider-cli` as the short-term tool bridge
2. keep hardening prompt + memory guidance so fact questions use canonical CLI paths
3. later build the true `AgentToolRegistry` bridge only after the CLI-backed workflow feels solid

---

## Current Ground Truth

For high-level vault totals, the canonical source should be:

- `cider-cli status --json`

This is the right source because `cider-cli` opens `.cider/cider.db` first and boots the same storage layer as the app.

As of April 14, 2026 in the current vault:

- bookmarks: `149`
- folders: `45`
- notes: `2`
- contacts: `2`

Important distinction:

- Codex process runtime is **not** querying SQLite directly
- but `cider-cli` is effectively the app-backed path into the SQLite-loaded state

So for count questions, the correct behavior is:

- use `cider-cli status --json`
- treat that as canonical
- only mention filesystem counts if the user explicitly asks for on-disk numbers or if there is a mismatch worth noting

---

## What Was Fixed

### 1. Telegram bridge works

Telegram polling, runtime routing, and response sending are working.

Relevant file:

- [TelegramBridge.swift](/Users/minivish/Cider/Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift)

### 2. Codex process launch works

The runtime can launch:

- `/usr/local/bin/codex app-server --listen stdio://`

The prior `node` / PATH problem was fixed in the process runtime environment setup.

Relevant file:

- [CodexProcessRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/CodexProcessRuntime.swift)

### 3. Initialize / thread start / turn flow works

The previous initialize timeout problem was fixed by:

- replacing fragile stdout line handling with buffered pipe reading
- adding startup timeout handling
- separating startup timeout from user-turn timeout

Current timeout split:

- startup timeout: `20s`
- turn timeout: `120s`

Relevant file:

- [CodexProcessRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/CodexProcessRuntime.swift)

### 4. Vault instructions are now injected from canonical memory

The process runtime prompt now prefers:

- `~/CiderVault/.cider/memory/agent.md`

with fallback to:

- `~/CiderVault/CLAUDE.md`

Relevant files:

- [AgentOrchestrator.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentOrchestrator.swift)
- [agent.md](/Users/minivish/CiderVault/.cider/memory/agent.md)

### 5. Count questions are now pinned to `cider-cli status --json`

The system prompt and canonical agent memory were tightened so count questions like:

- how many bookmarks do I have
- how many folders do I have
- how many notes / todos / contacts do I have

should use:

- `cider-cli status --json`

first, and treat that result as canonical.

This was done because the model previously mixed sources and could drift to raw filesystem counts.

Relevant files:

- [AgentOrchestrator.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentOrchestrator.swift)
- [agent.md](/Users/minivish/CiderVault/.cider/memory/agent.md)

---

## Important Clarification About "Tools"

There are two different meanings of "tools" in the current architecture.

### A. Native Cider app tools

These are the tools registered in `AgentToolRegistry`, for example:

- `countItems`
- `searchItems`
- `listFolders`
- `createNote`
- `addBookmark`

These are app-side, structured tool calls.

### B. Cider CLI commands

These are shell-invoked commands, for example:

- `cider-cli status --json`
- `cider-cli snapshot --json`
- `cider-cli bookmark list --json`

These are not native LLM tool calls, but they are still a valid tool bridge in practice because they go through the real app logic and the SQLite-backed storage layer.

Current state:

- the Codex runtime is using **B**
- the Codex runtime is **not** yet using **A**

This is why the runtime can answer vault questions now, but `supportsToolCalling` is still `false`.

---

## What Is Still Missing

The main missing piece is a true app-side tool bridge between `CodexProcessRuntime` and `AgentToolRegistry`.

Evidence:

- `CodexProcessRuntime.capabilities.supportsToolCalling` is still `false`
- prior logs showed Codex calling `list_mcp_resources` and receiving `{"resources":[]}`
- therefore no Cider vault resources were actually exposed through the Codex process runtime

Relevant files:

- [CodexProcessRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/CodexProcessRuntime.swift)
- [AgentToolRegistry.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentToolRegistry.swift)
- [AgentToolRegistration.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentToolRegistration.swift)

---

## Recommended Next Step

Short-term recommendation:

- continue using `cider-cli` as the process-runtime tool bridge
- keep the prompt / memory instructions explicit and conservative

Long-term recommendation:

- add a real process-runtime tool call bridge into `AgentToolRegistry`

Pragmatic sequence:

1. stabilize the current CLI-backed runtime path
2. verify real vault questions repeatedly through Telegram
3. then implement native tool-calling only after the CLI-backed path feels dependable

Reason:

- the CLI route already works
- it already uses app logic
- it already gives structured JSON
- it is much cheaper to stabilize than a fresh tool protocol bridge

---

## Concrete Files Touched In This Phase

- [CodexProcessRuntime.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/CodexProcessRuntime.swift)
- [AgentOrchestrator.swift](/Users/minivish/Cider/Sources/Cider/Services/Agent/AgentOrchestrator.swift)
- [TelegramBridge.swift](/Users/minivish/Cider/Sources/Cider/Services/Channels/Telegram/TelegramBridge.swift)
- [agent.md](/Users/minivish/CiderVault/.cider/memory/agent.md)

---

## Build Status

Verified on April 14, 2026:

- `swift build -c debug` passes

There are linker warnings from `libconvexmobile.a` being built for newer macOS point versions, but the build completes successfully.

---

## Good Resume Prompt For The Next Conversation

Use this prompt in the next thread:

> Read `/Users/minivish/Cider/Docs/Architecture/CODEX_TELEGRAM_HANDOFF_2026-04-14.md`, `/Users/minivish/Cider/Docs/Architecture/CODEX_HANDOFF_2026-04-14.md`, and `/Users/minivish/Cider/Docs/Architecture/AGENT_SERVICE.md`. Inspect the current `CodexProcessRuntime`, `AgentOrchestrator`, and Telegram bridge. Continue improving the Telegram-backed Codex runtime, keeping `cider-cli` as the short-term canonical tool bridge for vault facts and counts. Do not replace it with raw filesystem counting. If you implement native app-tool wiring, bridge it into `AgentToolRegistry` cleanly instead of adding a second ad hoc path.
