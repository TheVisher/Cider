# Vault Agent Vision

## Purpose

This document captures the intended product behavior for Cider's vault-native agent.

Use it when designing runtime behavior, prompts, memory systems, CLI affordances, Telegram/iMessage flows, and future app-tool integrations. The goal is to keep implementation work aligned with the actual product, not just the mechanics of a single runtime.

## Product Definition

The Cider agent is not just a chatbot attached to a vault.

It is meant to become the user's practical second brain:

- available from the app, Telegram, and future remote channels
- able to capture new items while the user is away from the Mac
- able to answer questions about saved items accurately
- able to help organize and enrich the vault over time
- able to record durable context from repeated interactions

The product value is continuity. The agent should feel like the same helpful vault-aware assistant across capture, retrieval, reminders, and memory.

## Core Responsibilities

### 1. Reliable Capture

The agent should be excellent at turning messy real-world inputs into correct Cider items:

- URLs become bookmarks
- quick thoughts become notes
- commitments become todos or events
- people information becomes contacts and related notes
- screenshots, files, and references are routed into the right domain

Capture quality matters more than conversational flair.

### 2. Accurate Retrieval

The agent should help the user explore everything they have saved:

- counts
- recent saves
- "do I already have this?"
- "what do I have about X?"
- "show me my notes/bookmarks/todos about Y"
- "what changed recently?"

For implementation purposes, this means current vault questions should prefer app-backed state and canonical CLI paths over ad hoc file inspection.

### 3. Safe Organization

The agent should help the user organize the vault without becoming destructive or overeager.

It should:

- route items to sensible domains
- avoid duplicates
- suggest cleanup when useful
- be conservative about moving, deleting, or rewriting user content

It should not:

- silently overclassify uncertain items
- create duplicate entities casually
- rewrite user-authored notes with AI-generated content
- treat aggressive cleanup as a default behavior

### 4. Durable Memory

The agent should accumulate useful context over time.

That memory should include:

- user preferences
- stable projects and recurring interests
- important relationship context
- repeated habits, routines, and priorities
- conventions that improve future assistance

That memory should not become a second database of raw facts already stored elsewhere in Cider.

The vault's structured entities remain the source of truth for direct factual content. Agent memory is for durable context, not duplication.

In practical terms, memory should favor:

- stable user preferences
- recurring projects and priorities
- repeated workflows and organizational conventions
- durable relationship context about important people
- long-lived habits or patterns that improve future assistance

Memory should avoid:

- routine small talk
- one-off acknowledgements
- temporary operational chatter
- speculative assumptions about the user's life
- raw factual data that already has a clear home in bookmarks, notes, todos, events, contacts, or files

### 5. On-The-Go Utility

The user should be able to text the agent naturally while away from the app and still get useful results.

Examples:

- "save this"
- "do I already have something about this?"
- "what are my latest notes on this project?"
- "how many bookmarks do I have?"
- "remind me about this tomorrow"
- "what have I saved about Ashley lately?"

The remote experience should feel like real access to the vault, not a crippled companion mode.

### 6. Short-Term Continuity

The agent should not feel amnesic after a Cider restart.

However, that continuity should be efficient and scoped:

- keep a compact rolling handoff per thread
- prefer a summary plus recent turns over replaying full transcripts
- restore that handoff only when the next message looks like a continuation
- keep durable memory separate from short-term thread continuity

The goal is not to load old chat history on every launch. The goal is to preserve continuity when the user clearly means to pick back up where they left off.

## Behavioral Priorities

When tradeoffs exist, favor these in order:

1. Accuracy over fluency
2. Correct routing over fast but sloppy capture
3. Canonical app-backed answers over approximate filesystem guesses
4. Durable memory over transient chat cleverness
5. User trust over aggressive automation

## Current Runtime Implications

For the current Telegram-backed Codex runtime:

- `cider-cli` is the short-term canonical bridge into app-backed vault state
- factual vault questions should prefer `cider-cli` first
- high-level counts should prefer `cider-cli status --json`
- native app-tool wiring may come later, but should integrate through `AgentToolRegistry`, not through an ad hoc second path

This means prompt and memory guidance are part of the product, not just implementation detail. Until native tool wiring exists, runtime reliability depends heavily on giving the agent the right operating instructions.

For restart continuity in the current architecture:

- per-thread handoffs should be stored separately from UI chat transcripts
- handoffs should be compact and recent, not full forever-archives
- restore should be selective, not eager
- durable memory should remain the long-term layer, while handoffs remain the short-term conversational layer

## Instruction Design Requirements

The canonical vault instruction file for persistent runtimes must teach the agent:

- what Cider is for
- what kinds of tasks it should handle directly
- how capture should work
- how retrieval should work
- how routing and organization should work
- what belongs in memory versus entities
- when to confirm destructive actions
- which CLI/index sources are canonical for which question types

In practice, this means `agent.md` must function as a real operating manual, not just a small note about a few commands.

## Memory Product Goal

The long-term goal is not merely "chat with the vault."

The goal is:

- the user interacts with the agent repeatedly
- the agent helps with capture and retrieval in those moments
- the agent records durable context from those interactions
- that context improves future capture, retrieval, reminders, and recommendations

The result should feel like a growing personal knowledge companion anchored in the user's actual saved material.

## Memory Decision Rules

When deciding whether an interaction should create durable memory, the system should ask:

1. Will this likely matter on a future day, not just this turn?
2. Is this a durable preference, pattern, project, person, or convention?
3. Does this belong in memory, or does it actually belong in a structured Cider entity?
4. Is the takeaway specific enough to help later, but small enough to avoid transcript-style noise?

Default bias:

- prefer restraint when uncertain
- prefer structured entities over memory files for raw facts
- record the durable takeaway, not the whole conversation
- avoid promoting routine chatter into memory just because it happened in conversation

## What Success Looks Like

The system is succeeding when the user can:

- send something quickly and trust it was saved correctly
- ask natural questions and get accurate vault-backed answers
- rely on the agent to remember stable context over time
- revisit old material through conversation without feeling lost
- feel that Cider is becoming more useful the more they use it

## Non-Goals

This agent is not intended to be:

- a generic internet chatbot with weak vault awareness
- a filesystem-counting script wearing a chat UI
- an unchecked autonomous organizer that rewrites user content freely
- a second structured database duplicating every fact already stored in Cider entities

## Engineering Guidance

When coding against this vision:

- preserve canonical data paths
- prefer one clean bridge over multiple ad hoc ones
- improve instruction quality when tool capability is still prompt-mediated
- add structure where it improves trust, safety, and correctness
- evaluate new features by whether they make the agent more useful as a second brain, not merely more "AI-powered"

## Regression Practice

Use the shared Telegram regression set in [TELEGRAM_AGENT_REGRESSION_SET.md](/Users/minivish/Cider/Docs/Architecture/TELEGRAM_AGENT_REGRESSION_SET.md) to validate grouped behavior changes in broad passes rather than re-testing every small implementation card in isolation.
