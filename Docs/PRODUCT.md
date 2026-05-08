# Cider Product

Status: canonical core doc.

Cider is a local-first Mac second brain and life command center: one place on the user's machine to capture and organize digital life, remember bills/events/reminders, control daily workflows, and talk to the user's main agent.

## Product Principles

- Local-first by default. The vault and SQLite database are the source of truth for personal data.
- Fast capture matters more than perfect categorization at capture time.
- Cider should help the user remember, resurface, connect, and act.
- Cider is practical memory support, not vague productivity theater. It should notice gaps, resurface useful context, and reduce the cost of remembering.
- Conservative routing beats clever misfiling. When confidence is low, keep the item visible in Inbox and ask.
- Dashboard cards, reminders, and agent reports should explain why something matters, not just that something exists. Cider should compute relevance once in a shared agenda/briefing layer, then let Dashboard, CLI JSON, Telegram, and agents render that same truth.
- Kanban is the product's work surface for roadmap, QA, bugs, and implementation history.
- Docs should stay lean and durable.
- Agents should be useful, cautious, and report what they changed.

## Current Focus

1. Make Cider's docs model lean: core docs for durable development knowledge, Kanban for roadmap and QA.
2. Keep Kanban strong as the active planning and verification surface.
3. Improve Main Brain reliability so Cider chat can stand in for remote Hermes workflows when the user is at the Mac.
4. Turn Dashboard/Home into a useful second-brain command center rather than a static feed.
5. Keep capture reliable across bookmarks, notes, files, todos, contacts, dates, and screen capture.

## Product Shape

Cider should feel like:

- a Mac-native command palette and floating panel
- a local vault client
- a capture inbox
- a searchable memory system
- a personal project board
- a focused chat surface for the user's main agent

It should not become:

- a generic feed reader
- a heavy project-management clone
- a pile of stale Markdown plans
- a multi-agent roster before the main Cider brain feels excellent

## Product Decisions

- Sidebar is for organization. Tabs and saved views are for views into the vault.
- Home/Dashboard is the command center, not a generic news feed.
- Saved Views absorb many older project/stacks concepts; avoid reintroducing a separate project system without a clear reason.
- Time is metadata. Importance is presentation and prioritization, not a separate storage location.
- Cider-owned reminders and tasks are product data; external systems can be delivery channels or fallbacks.
- Main Brain parity matters more than a broad agent roster. Make the one native Cider brain excellent first.

## Roadmap Ownership

Roadmap items live in Kanban. This doc may summarize current direction, but it should not become a second roadmap.
