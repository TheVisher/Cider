# Cider Product

Status: canonical core doc.

Cider is a local-first Mac second brain and life command center. It is the user's calm native memory cockpit: fast capture, clear review, helpful resurfacing, and trusted Hermes access to local personal context.

In everyday use, conversation and voice-driven Journal capture remain important intake paths, but the native Mac app opens to Home by default. Home is a compact Today view rather than a broad dashboard; Journal is a permanent top-level destination. Cider Chat is the first-class native conversational destination on Mac, with shared client-neutral room contracts for a later web client. The Mac app also remains an important manual-capture, browsing, review, and project-management client; no capture path is required to pass through Chat.

The destination is defined in `Docs/NORTH_STAR.md`; this document summarizes the current product line, principles, surfaces, focus, and non-goals.

The product is no longer the old general vault/bookmark app with extra features bolted on. Bookmarks, notes, files, todos, dates, contacts, screenshots, Kanban cards, and Spaces are parts of one second-brain system.

The core loop is:

1. Capture quickly.
2. Enrich when possible.
3. Route conservatively.
4. Review uncertainty.
5. Resurface useful context and actions.

## Product Principles

- Local-first by default. Personal memory belongs on the user's Mac first.
- Capture must be fast and imperfect by design. The user should not need to decide the perfect folder, type, or tag before saving something.
- Manual and agent captures must have parity: both enter the same canonical item/index/provenance graph and must be equally available to search, recall, linking, review, and Main Brain.
- Journal is the readable chronological narrative. Explicit user intent creates typed bookmarks, places, tasks, events, and other objects linked to that narrative; incidental mentions remain reviewable suggestions rather than automatic Library clutter.
- Cider should reduce memory and ADHD friction by helping the user remember, connect, review, and act.
- SQLite is the canonical memory and query layer for managed items, routing, review state, search, recall, agenda relevance, and agent context.
- Vault files and Kanban YAML remain durable artifacts and workflow stores where the file itself matters.
- Conservative routing beats clever misfiling. When confidence is low, Cider should keep uncertainty visible in review instead of hiding a bad guess.
- Dashboard, reminders, CLI JSON, and agent reports should share the same relevance truth and explain why something matters.
- Hermes is the sole supported current execution runtime, but Cider owns Chat rooms, participant identity, routing preferences, visibility, history, and user-facing controls. Other agents remain explicit bounded participants behind replaceable runtime bindings; Cider should not become a provider credential or runtime-administration console.
- Kanban is Cider's active roadmap, spec, testing, bug, and handoff surface.
- Core docs should stay lean and durable.

## Product Surfaces

- Home is the default native Cider opening surface: a compact Today view over relevant local second-brain state.
- Journal is the permanent top-level chronological life narrative.
- Cider Chat is the native room-based conversation surface. Each room has one head agent for ordinary unaddressed conversation and may include explicitly invoked participants whose work detail can be disclosed or filtered without fragmenting canonical history.
- Capture is the lowest-friction intake path for URLs, Journal entries, notes, files/images, tasks, dates, contacts, and snippets.
- Review is a contextual trust workflow for uncertain routing, metadata, duplicates, reminders, and agent suggestions.
- Library opens to the complete visual collection with calm type, state, and Space/entity filtering.
- Spaces are entity-aware semantic hubs/lenses under Library, not top-level silos or mere saved filters.
- Projects opens to a calm cross-project summary; entering a project opens its Kanban Board.
- Kanban is the product and development operating layer for roadmap work, QA, bugs, and agent handoff memory.
- CLI is the agent-facing command surface for reliable inspection and mutation.

## Current Focus

1. Run a product-scope reset through an explicit feature/view/route inventory; preserve content while deciding what to keep, merge, demote, park, or remove.
2. Make conversation -> Journal -> selective typed objects -> source-backed recall the first mature daily loop.
3. Guarantee parity between native/manual capture and agent capture through the shared SQLite-backed item, provenance, indexing, review, and recall layer. Library opens to the complete visual collection with calm, easily cleared show/hide filters over that shared data.
4. Add bounded reconciliation for relationships discovered across time, such as a later manual toolbox bookmark matching an earlier Journal intention, while keeping uncertain links reviewable.
5. Keep Kanban strong as the visual idea, project, QA, and agent-handoff system without treating every captured idea as immediate implementation work.
6. Stabilize speed, reliability, and Testing debt before broad feature expansion.
7. Place Spaces under Library as entity-aware semantic hubs/lenses. Allow useful domain-specific states and workflows—such as watched/unwatched and liked/disliked for movies—without creating parallel storage or permanent top-level mini-apps.

## Legacy Framing

Cider still keeps important older capabilities, but they should now serve the second-brain model.

- Bookmarks are one captured item type, not the product center.
- Notes and files are durable memory artifacts plus searchable context.
- Folders and Tags remain preserved storage/metadata capabilities but are parked from default Library UI until observed organization friction justifies a focused surface.
- Todos, dates, contacts, and reminders are life-memory objects, not side utilities.
- Spaces are lenses over shared state, not separate storage systems.
- Kanban is first-class as Cider's own work surface and agent handoff system, but Cider should not become a heavy project-management clone.
- Historical Markdown plans, stale bug notes, and old roadmap clutter belong in Kanban or git history, not active docs.

## Non-Goals

- Do not turn Cider into a cloud-first app.
- Do not ship legacy Account/Sync UI or claim sync value before a real second platform/client exists; preserve a narrow compatibility seam and redesign when multi-client use becomes concrete.
- Do not make Spaces independent data silos.
- Do not make docs the roadmap.
- Do not build clever auto-filing that hides uncertainty from the user.
- Do not build a generic feed reader.
- Do not turn Chat into a noisy always-visible multi-agent roster. Keep one clear head agent per room, explicit participant invocation, independent routing and visibility controls, and progressive disclosure of agent work.
- Do not preserve old Cider behavior as active direction just because it exists in legacy history.

## Roadmap Ownership

The active roadmap lives in Kanban, especially the Cider board (`2afee0`). This doc is the durable product narrative; it should not become a duplicate roadmap, QA report, or implementation log.

The pre-second-brain product line is preserved in git on `legacy/pre-second-brain-cider` for reference. It is not the default direction for new work.
