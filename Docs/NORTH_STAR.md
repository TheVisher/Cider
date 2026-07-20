# Cider North Star

Status: canonical core doc.

This document is the guiding product direction for Cider. It should be read before broad Cider development, architecture audits, agent prompts, major refactors, or feature work that touches capture, recall, routing, relationships, Spaces, Main Brain, Dashboard, reminders, or the second-brain graph.

`Docs/PRODUCT.md` explains the current product line. This doc explains the destination agents should optimize toward.

## The North Star

Cider is a local-first life operating system and second brain for one person first.

It should help the user:

1. Capture real-life context with low friction.
2. Preserve where each piece of context came from.
3. Link context to the right people, projects, places, dates, tasks, media, decisions, and artifacts.
4. Recall the right context later through search, chat, dashboards, and agent tools.
5. Resurface timely context before the user has to remember to ask.
6. Act safely on local personal data without hiding uncertainty or damaging trust.

Cider is not primarily a bookmark manager, notes app, file browser, Kanban clone, chat shell, or folder organizer. Those are surfaces over one shared second-brain system.

## Product Shape

The durable Cider loop is:

```text
capture -> enrich -> route -> review -> link -> recall -> resurface -> act
```

Every major feature should either strengthen that loop or deliberately stay out of the way.

## Whole-Life Planning And Time Sovereignty

Cider's long-term value is not merely remembering separate facts about work, money, plans, messages, browsing, and daily life. It should connect those facts into a source-backed model that helps the user make better decisions while protecting the resource that matters most: personal time.

With explicit authorization and appropriate privacy boundaries, Cider should be able to combine:

- paystubs, timecards, hourly rates, lead premiums, overtime and double-time rules, taxes, withholding, and observed take-home pay;
- bank and credit-card balances and transactions, recurring bills, rent, debt, savings, and financial obligations;
- email receipts, statements, purchase notices, travel confirmations, and other source evidence;
- Journal entries and conversations about goals, purchases, trips, stress, work tolerance, family plans, and changing priorities;
- bookmarks and browsing context for products, hotels, flights, parks, restaurants, media, vehicles, and places;
- current web research for real prices, availability, schedules, and options.

The target experience is a grounded planning conversation. If the user says, “I want to take a ten-day Disneyland trip in six months,” or “I want to buy this item while working as little overtime as possible,” Cider should be able to:

1. Research and itemize the likely total cost with dated sources and uncertainty ranges.
2. Read the user's current cash flow, debt, bills, balances, and expected income from authorized sources.
3. Estimate future checks from confirmed wage rules and observed pay history without presenting guesses as payroll truth.
4. Compare scenarios such as no overtime, one overtime weekend, faster debt payoff, or a later goal date.
5. Explain the minimum extra hours or shifts, per-paycheck savings target, and timing needed to keep bills paid and reach the goal.
6. Recalculate when a paystub, timecard, transaction, bill, price, or plan changes.
7. Show which facts are confirmed, inferred, stale, missing, or user-adjustable.

This is not a generic budgeting dashboard and not an excuse for hidden financial automation. The Finance surface remains a clear dashboard over canonical data; Main Brain provides the reasoning and scenario conversation. Recommendations must be explainable, reversible, source-backed, privacy-bounded, and conservative about tax, payroll, and future-price uncertainty.

The human outcome is **time sovereignty**. Cider should help the user get debt and obligations under control, protect savings and family goals, and then minimize unwanted overtime. More income is not automatically the objective; the objective is the least work and sacrifice needed to achieve the life the user actually wants.

## Primary Interaction And Capture Parity

Conversation and voice-driven Journal capture are Cider's primary everyday front door. The user should be able to talk naturally, explicitly ask Cider to remember or create something, and later recall it with source-backed accuracy even when the native Mac app has not been opened for days.

The native app remains a first-class manual capture and visual-management client. A bookmark, image, file, note, task, event, or other item saved manually must enter the same canonical item, provenance, indexing, linking, and recall system as an agent-created capture. Manual and agent captures must be equally visible to Main Brain and other authorized agents.

- The Journal is the readable chronological narrative, not the only object type and not a raw transcript dump.
- Explicit intent such as “save this,” “remind me,” “make this a task,” or “add this restaurant” may create the corresponding typed object immediately and link it to the source Journal/conversation entry.
- Ordinary mentions may produce reviewable people/place/task/date/preference/relation candidates, but should not silently create Library clutter or accepted truth.
- URLs, images, and files captured manually or conversationally preserve their own identity while linking back to the source episode or context that made them meaningful.
- Bounded daily/weekly reconciliation may scan new Journal entries and newly captured items for missed reciprocal relationships. It should propose source-backed links for review, deduplicate against existing relations, and never silently promote ambiguous matches to accepted graph truth.

- Capture gets material into Cider quickly, even when metadata is incomplete.
- Enrichment extracts useful structure without overwriting user-owned truth.
- Routing proposes where something belongs, with confidence and evidence.
- Review keeps uncertainty visible instead of silently making bad decisions.
- Linking connects items into a traceable graph of real-life meaning.
- Recall retrieves context through exact search, structured filters, graph expansion, and agent context bundles.
- Resurfacing brings reminders, follow-ups, dates, stale inbox items, project state, and relationship context back at the useful time.
- Acting lets the user or agent update, complete, route, relate, schedule, summarize, or hand off with safety rails.

## First-Class Memory Objects

Cider should treat these as durable parts of the same personal knowledge graph:

- people and contacts
- projects and ongoing work
- places and restaurants
- dates, events, todos, reminders, and recurring obligations
- notes, journals, files, images, screenshots, and voice-derived captures
- bookmarks, media, recipes, products, reference material, and plans
- Kanban boards/cards, QA evidence, implementation history, and handoff context
- agent conversations, captures, actions, decisions, and provenance

A person, project, or place should become a hub of related context, not a string that each feature interprets differently. If the user repeatedly mentions a person across journal entries, reminders, restaurant notes, plans, messages, and saved links, Cider's long-term direction is to make that relationship inspectable and useful through explicit relations, reviewable candidates, and safe context bundles.

## Relationship And Backlink Direction

Cider's linking model should be explicit, inspectable, and reviewable.

- Prefer typed relations over vague text inference when a relationship matters.
- Preserve source/provenance for generated or suggested links.
- Make similarity and entity candidates reviewable before they reorganize user memory.
- Keep backlinks visible enough that users and agents can understand why items are related.
- Merge or link before creating duplicate entities.
- Do not let folders, tags, or LLM summaries become hidden authorities for identity.

The target is not magical auto-organization. The target is a trustworthy graph where agents can say: this note, reminder, bookmark, and plan are connected to this person/project/place for these reasons, and here is what is confirmed versus suggested.

## Surfaces And Roles

Cider should have multiple surfaces, but one shared memory foundation. No chat app, transport, or hosted LLM provider should become the source of truth for the relationship between the user and Cider/Hermes. Discord, iMessage/Photon, the native app, CLI, and future surfaces are interchangeable doors into the same local-first system.

- **Main Brain/Hermes** is the agent runtime and conversational surface over Cider truth, used primarily outside the native Mac app for now. Preserve its integration and route compatibility without requiring permanent app navigation weight.
- **iMessage/Photon** is a low-friction personal front door for quick capture, reminders, voice notes, recall, and high-attention nudges; it is not the canonical conversation system.
- **Discord** is a structured operations cockpit for development, debugging, Cody handoffs, screenshots, files, threads, and channel-specific workflows; it is not the canonical conversation system.
- **Dashboard/Home** is the today/now command center: what matters, why it matters, and what action is available.
- **Capture** is the fast intake layer for URLs, text, files, screenshots, voice, tasks, dates, contacts, and snippets.
- **Review Queue** is the trust boundary for uncertain routing, metadata, duplicates, reminders, links, and agent suggestions.
- **Spaces** are domain lenses over shared memory, not independent silos. Media, Food, People, Projects, Finance, Recipes, and future Spaces should share item identity, routing, review, relationships, and recall.
- **Library** is the searchable inventory of saved and managed items.
- **Kanban** is Cider's roadmap, QA, implementation, bug, and handoff operating layer.
- **CLI** is the reliable agent-facing interface for facts and safe mutations.

If two surfaces need the same truth, build or use the shared service/read-model instead of duplicating logic in each view.

Home is the confirmed default opening experience and remains a compact Today view for reminders, open loops, and genuinely relevant resurfacing—not a broad administrative dashboard. Journal is a permanent top-level destination. Library and Projects/Kanban remain core destinations. The bare in-app Main Brain surface is parked from normal navigation while Hermes integration, route compatibility, and future conversational capability remain preserved. Review is a contextual trust workflow that appears when needed rather than occupying permanent navigation. Spaces live under Library as entity-aware semantic hubs/lenses, not as another top-level mini-app system; they may provide domain-specific states, facets, and actions while sharing canonical Cider data. Other specialized views must earn navigation weight through clear repeated value and may be demoted, merged, hidden, or parked without deleting underlying data or capability.

When product breadth becomes overwhelming, prefer a deliberate feature/view/route inventory with the user over speculative expansion. Classify each surface as keep, merge, demote, park, or remove; preserve content and durable capability before changing navigation or deleting code.

## Local-First Trust Contract

Cider should be safe enough for real personal life context.

- The Mac/local vault is the primary authority.
- SQLite is the canonical metadata, query, graph, routing, review, and agent-context layer for managed items.
- Vault files remain durable user-visible artifacts where the file matters.
- Kanban YAML remains canonical for board/card workflow while SQLite projections make it searchable and agent-readable.
- Sync and remote clients are secondary to local data safety.
- Destructive actions must use trash/undo/approval flows, not direct deletion.
- Generated AI content belongs in AI-owned fields unless the user explicitly approves a user-owned edit.
- Low-confidence routing or linking belongs in review, not hidden automation.

## Agent Contract

Agents working on or through Cider should behave like careful operators over a living personal memory system.

Agents should:

- use `cider-cli` and Cider services before raw files or SQLite;
- preserve provenance for captures, attachments, routing, relations, and actions;
- ask clarifying questions when routing, metadata, or expected behavior is below high confidence;
- prefer Inbox/review over wrong automatic organization;
- inspect item/project/owner context and graph health before changing organization behavior;
- record implementation history, failed attempts, QA evidence, and handoffs on Kanban cards;
- promote only durable product, architecture, storage, CLI, QA, design, convention, or agent-behavior decisions into core docs;
- keep user-facing summaries concise and practical;
- use voice/TTS when the user is interacting by voice and likely driving or walking.
- keep the conversational head available by dispatching long coding, research, machine-operation, and broad-verification work to named executors early, returning a durable receipt, and ending the head turn promptly.

Agents should not:

- rewrite Cider from scratch to satisfy a local task;
- create parallel memory systems outside Cider's item graph and capture provenance;
- silently mutate user-owned fields based on AI guesses;
- infer truth from folder paths, tags, sidecars, old docs, or LLM memory when Cider has a structured command;
- turn temporary plans, audits, or task notes into permanent docs;
- optimize a feature surface in isolation when it should use shared capture, routing, review, linking, or recall services.

## Development Alignment Tests

Before implementing broad Cider work, ask:

1. Does this strengthen capture, recall, resurfacing, relationships, or trust?
2. Does it use the shared second-brain graph/storage model instead of inventing a feature-only path?
3. Does it preserve item identity, provenance, and safe mutation rules?
4. Does it make uncertainty visible and reviewable?
5. Does it improve agent access through structured CLI/service output?
6. Does it keep Spaces as lenses over shared memory rather than silos?
7. Does it make Dashboard/Home, reminders, or agent briefings more explainable?
8. Does it avoid adding another hidden pile, duplicate route, or Markdown scratchpad?
9. Can the result be verified with focused tests, CLI JSON, or visible UI evidence?
10. Would another agent understand how this change fits the North Star from the card, docs, and code?

If the answer is no, the work likely needs a smaller scope, a shared-service design, a Kanban card, or an explicit product decision before implementation.

## Future-Agent Prompt Shape

When giving Cider to a powerful coding agent, do not ask for an unbounded rewrite.

Prefer prompts shaped like:

```text
Read Docs/NORTH_STAR.md, Docs/PRODUCT.md, Docs/ARCHITECTURE.md, Docs/STORAGE.md, Docs/AGENT.md, and the relevant Kanban card.
Preserve Cider's local-first vault, SQLite second-brain graph, capture provenance, routing/review trust boundary, Spaces-as-lenses model, design language, and existing user data.
Audit or implement the smallest scoped change that moves Cider toward the North Star.
Record findings, evidence, and follow-up work on Kanban.
Do not rewrite from scratch or create a parallel data model.
```

Useful agent jobs include:

- audit current routes and views against the shared second-brain model;
- find feature-only storage paths that should project into the item graph;
- improve relationship/backlink visibility for people, projects, places, and captures;
- make Dashboard/Home consume shared relevance truth;
- improve capture -> routing -> review receipts and agent-safe JSON;
- remove or park legacy surfaces after preserving durable intent;
- implement one bounded feature slice with tests and UI/CLI verification.

## Non-Goals

- Cider should not become cloud-first.
- Cider should not depend on one hosted LLM provider, one runtime session system, or one communication transport.
- Cider should not hide bad guesses behind confident automation.
- Cider should not make Spaces, folders, tags, dashboards, agent memory, or Markdown docs compete as separate truths.
- Cider should not grow a broad agent roster before Main Brain is excellent.
- Cider should not keep legacy surfaces alive just because they exist.
- Cider should not let a model produce giant unreviewable diffs that cannot be tied to cards, tests, and durable product direction.

## How This Doc Should Evolve

Keep this document durable and compact. It should change when the product direction changes, not after every feature.

- Put roadmap, bugs, implementation plans, QA evidence, and handoff history on Kanban.
- Put storage contracts in `Docs/STORAGE.md`.
- Put feature inventory in `Docs/FEATURES.md`.
- Put detailed agent operating rules in `Docs/AGENT.md`.
- Put visual rules in `Docs/DESIGN.md`.
- Put temporary prompts or audit outputs in project artifacts or cards, then harvest durable decisions here if they become product direction.
