# Kanban Product

## Product Promise

Kanban is Cider's active work surface: a calm place to turn conversations, ideas, bugs, and implementation handoffs into visible work without turning every thought into another Markdown file.

## Product Model

Docs and Kanban have different jobs:

- Docs are durable foundation records.
- Kanban cards are active work and handoff records.
- Big or lasting Kanban outcomes graduate into docs.
- Small tasks, bugs, polish, review findings, and temporary coordination stay on cards.

## Current Behavior

- Boards appear as Cider tabs.
- A board contains named columns and compact cards.
- Columns can be marked as done columns.
- Moving a card into a done column sets `completed`.
- Moving a card out of a non-done column clears `completed`.
- Clicking a card opens the shared Cider slide-out detail panel.
- The card detail panel supports long-form notes/spec text directly on the card.
- Metadata includes board/status, priority, color, agent, tags, linked items, dates, export, and delete.
- Markdown export is explicit and uses the current card draft.

## Product Principles

- Kanban is a lens over Cider work, not an isolated mini-app.
- Cards can hold serious product/refactor notes without creating extra vault notes by default.
- Compact board cards should stay scannable.
- Big ideas should not become one forever-card with thousands of lines of notes. Use a parent card for the overarching idea and scoped child cards for implementation parts, bugs, fixes, and test follow-ups.
- Parent/child card structure should create a visual roadmap: the user and agents can see what remains, what order to work in, and what history led to the current fix without reading a huge Markdown file.
- Child cards may have children when a scoped slice reveals smaller bugs or follow-ups. The board should keep nested visuals shallow and readable; the detail panel should show the full lineage/breadcrumb.
- Parent groups can be moved into `Queued` to stage a plan; individual child cards should then move one at a time through `In Progress`, `Testing`, and `Done`.
- Visual hierarchy matters for ADHD-friendly comprehension: cards should be bite-sized, grouped, linked, and collapsible where possible.
- The slide-out detail panel should feel consistent with other Cider cards.
- Metadata is secondary to the main job: read/write the brief and move work forward.
- Agents should use Kanban for active coordination and docs for durable truth.

## Non-Goals

- Do not create a Markdown note for every Kanban card.
- Do not use Kanban as the permanent product bible.
- Do not let duplicate card history substitute for current source-of-truth docs.
- Do not let multiple agents mutate board YAML at the same time.

