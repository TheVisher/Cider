# Cider Dashboard Design

> Status: historical design context. The current Dashboard source of truth lives in `Docs/Features/Dashboard/`.

**Date:** 2026-04-19
**Status:** Historical approved design

## Summary

Design a new Home dashboard for Cider that feels like a cinematic vault command center rather than a generic mixed-content feed.

The dashboard should preserve the moody, instrument-panel feel of the visual reference, but the content should be native to Cider's vault model: notes, bookmarks, todos, events, contacts, and files. The default experience should prioritize `vault overview`, not daily planning and not a full assistant workspace.

The implementation for `v1` should ship as a polished fixed layout, but the internal architecture should already be modular enough to support future panel swapping, show/hide settings, and panel resizing without forcing a rewrite later.

## Problem

The current Home experience is useful as a mixed-content library feed, but it does not yet feel like a true dashboard:

- it does not provide a strong at-a-glance orientation to the state of the vault
- counts, triage, resurfacing, projects, and scheduling are not composed into one coherent overview surface
- the screen does not yet express distinct panel identities the way a real dashboard should
- the current architecture risks drifting toward a one-off home screen if a richer dashboard is added without modular boundaries

The product opportunity is to make Home feel like the place users open when they want to understand what matters in their vault right now.

## Goals

- Create a visually distinctive Home dashboard inspired by the reference image's cinematic multi-panel layout.
- Make the dashboard primarily a `vault overview`.
- Reserve the main grid for actionable or orienting information, not raw totals.
- Surface triage, recent activity, upcoming items, resurfacing, and active projects in one coherent composition.
- Give each dashboard panel a distinct internal visual language.
- Build the internals as a modular system that can support future swapping, show/hide settings, and resizing.

## Non-Goals

- No user-driven panel rearranging in `v1`.
- No user-facing panel resizing in `v1`.
- No full embedded AI chat panel in `v1`.
- No attempt to replace the full calendar, search, or assistant experiences with this dashboard.
- No generic dashboard engine with complete customization controls in this pass.

## Product Direction

### Chosen direction: curated modular dashboard

The recommended direction is a `curated modular dashboard`.

This means:

- `v1` ships one polished default composition rather than a blank or user-configured canvas
- each panel is still implemented as a stable module with layout metadata and a bounded data surface
- the layout foundation is designed with future swapping and resizing in mind, even though those controls do not ship yet

This is the right balance between polish and long-term flexibility.

### Rejected alternatives

#### Hardcoded cinematic dashboard

Building the dashboard as one highly specific one-off screen would be faster in the short term, but it would make future customization much harder.

#### Fully generic dashboard engine

Building a full registry, settings, slot editor, and resizing system now would over-abstract the problem and slow down the actual Home redesign.

## Layout Foundation

The dashboard should use a curated multi-row composition derived from the selected `A-style` concept explored during brainstorming.

High-level structure:

1. top telemetry strip
2. top hero row
3. middle activity and schedule row
4. bottom resurfacing and projects row

### Top telemetry strip

The top-right strip should act as a compact instrument cluster for lightweight vault-wide metrics. This is intentionally not a full panel. Its purpose is to hold glanceable totals and health signals so the main grid can stay focused on meaningful content.

Default metrics:

- `Bookmarks`
- `Notes`
- `Todos`
- `Events`
- `Unfiled`
- `Urgent`
- `Docs Health`

Future dashboard settings can allow users to show or hide metrics, but `v1` can ship with a fixed default set. `Docs Health` should summarize documentation rot: stale docs, broken references, duplicate/conflicting docs, and docs that no longer match current code.

### Hero row

The top content row contains:

- `Vault Pulse`
- `Overview`
- `Needs Attention`

The `Overview` panel is the narrative anchor and is allowed to be slightly taller than an ordinary compact card so its full summary and chips always fit without clipping. Neighboring panels in the row should stretch to preserve clean row alignment.

This is an explicit design rule for `v1`: hero content fits first, and alignment is preserved at the row level rather than by forcing every panel to share the same internal visual weight.

### Middle row

The middle row contains:

- `Recent Activity`
- `Today + Upcoming`
- the continuing height of `Needs Attention`

This row should feel dynamic and information-rich, but each panel must use a different internal structure so the screen reads like a dashboard rather than one repeated card style.

### Bottom row

The bottom row contains:

- `Resurface`
- `Pinned Projects`

This row should feel slightly slower and more reflective than the middle row. Resurfacing is about rediscovery, while projects represent ongoing thematic work.

## Default Panel Set

The default dashboard should ship with seven visible modules plus the telemetry strip.

### Telemetry Strip

Purpose: hold lightweight vault-wide counts and health signals.

Behavior:

- glanceable first
- may be clickable into filtered views or queues
- modeled as a list of metric items so future settings can show/hide/reorder them

### Vault Pulse

Purpose: provide a qualitative read of the vault at a glance, like "Active, slightly backlogged."

Behavior:

- ambient and short
- low-interaction compared with operational panels
- should not compete with the Overview panel

### Overview

Purpose: act as the narrative center of the dashboard.

Content:

- one or two sentences summarizing the current state of the vault
- a handful of high-signal chips such as `recent captures`, `unfiled`, `due today`, or `resurfaced`

Behavior:

- chips should be actionable
- full content must always fit
- this panel should feel like orientation, not just a count dump

### Needs Attention

Purpose: operational triage.

Content:

- compact metrics like `Unfiled`, `Missing tags`, `Due today`, `Untitled notes`, and `Docs Health`
- direct shortcuts into high-priority queues
- report-only documentation rot findings: stale docs, broken references, duplicate/conflicting docs, and docs that no longer match current code

Behavior:

- highly actionable
- answers "what requires intervention right now?"
- documentation findings should show short reasons and suggested actions, but should not auto-edit/delete docs unless the user approves cleanup

### Recent Activity

Purpose: show the latest meaningful changes across the vault.

Visual treatment:

- timeline-like, not generic repeated rows

Content examples:

- new captures
- edited notes
- completed or updated todos
- contact updates
- bookmark saves

Behavior:

- clicking an entry opens the underlying item

### Today + Upcoming

Purpose: surface imminent schedule-related work without becoming a full calendar app.

Visual treatment:

- mini day strip or calendar ribbon across the top
- focused agenda below

Behavior:

- clicking an item opens the underlying date card or todo
- visually temporal rather than list-like

### Resurface

Purpose: bring back neglected but currently relevant items.

Visual treatment:

- thumbnail-style or preview-driven cards
- not plain text rows

Behavior:

- clicking a resurfaced card opens the underlying item
- the panel should already be designed to adapt to richer or larger previews in future resizable states

### Pinned Projects

Purpose: represent longer-horizon active work.

Visual treatment:

- progress-oriented blocks
- can reflect projects, folders, saved views, or another curated source

Behavior:

- clicking opens the associated project, view, or grouping
- this panel should also tolerate future width and height changes gracefully

## Panel Identity Rules

Each panel must earn its footprint with a distinct internal visual language. The dashboard should not feel like the same rounded sub-card repeated in different places.

Recommended visual grammar:

- `Vault Pulse`: short atmospheric summary
- `Overview`: narrative summary plus chips
- `Needs Attention`: metric blocks plus direct links
- `Recent Activity`: timeline
- `Today + Upcoming`: calendar strip plus agenda
- `Resurface`: visual rediscovery cards or thumbnails
- `Pinned Projects`: progress cards

This rule is important enough to treat as a design constraint, not a styling preference.

## Modular Foundation

Under the hood, the dashboard should be built as a modular system rather than one large hardcoded view.

Each panel should have:

- a stable `panel ID`
- a `panel kind`
- layout metadata
- size metadata
- a bounded rendering surface
- a bounded data surface

### Shell and panel boundaries

Recommended separation:

- `dashboard shell` handles composition, telemetry strip, slots, and shared chrome
- `panel modules` render distinct dashboard sections
- `panel data providers` prepare the narrow inputs needed by each panel
- future `dashboard settings` sit above this system as a visibility and configuration layer

### Layout metadata

Even though `v1` does not ship rearranging or resizing controls, the layout should already be represented as structured metadata rather than only implicit nesting in a view body.

The system should be able to express:

- which panel occupies which slot in the default layout
- row or slot sizing preferences
- panel minimum and ideal sizes
- which panels are allowed to expand or compress more than others

This is the key design bridge to future customization.

### Future resizing readiness

Future resizing is explicitly part of the intended direction, even though it is not a `v1` feature.

That means panels should be designed now as if they may eventually appear in different shapes:

- wider
- narrower
- taller
- shorter

Panel internals should avoid relying on one exact fixed size forever. For example:

- `Resurface` should be able to grow from compact thumbnails to roomier previews
- `Pinned Projects` should tolerate denser or more spacious progress cards
- `Today + Upcoming` should treat its day strip as a reusable scheduling subcomponent that can adapt to more or less room

The `v1` implementation should not expose resizing controls, but the architecture should assume resizing may arrive later.

## Data Flow

The dashboard should feel read-mostly at first glance, but every meaningful element should lead somewhere useful.

### Telemetry Strip

Each metric should map to a relevant filtered destination, such as:

- `Unfiled` -> inbox-style view
- `Urgent` -> due or approaching queue
- entity counts -> relevant saved view or filtered library view

### Overview

The chips are the main interaction target. Clicking a chip should open the queue or filtered view implied by that signal.

### Vault Pulse

Low interaction in `v1`. It can remain mostly informational.

### Needs Attention

Every metric and shortcut should route directly into an actionable queue, saved view, or focused list.

### Recent Activity

Every timeline entry should open the underlying item.

### Today + Upcoming

Every surfaced item should open the relevant date card or todo.

### Resurface

Every resurfaced card should open the underlying item.

### Pinned Projects

Each project block should open its associated project, folder, or saved view.

## Data Provider Shape

The dashboard should not rely on ad hoc state access from every panel.

Preferred shape:

- a dashboard-level coordinator gathers broad Home data
- each panel receives pre-shaped data or uses a narrowly scoped provider
- panel logic stays local and replaceable

This keeps the system easier to evolve and test.

## Testing Considerations

This design should be validated both visually and behaviorally.

Recommended testing focus:

1. The dashboard should remain legible and balanced at the panel's supported Home widths.
2. The `Overview` panel must never clip its content.
3. Each panel should have a distinct internal structure that remains visually differentiated.
4. Clicking a metric, chip, activity item, schedule item, resurfaced card, or project block should route to the correct destination.
5. The modular structure should make it straightforward to hide or replace a panel later without destabilizing the rest of Home.

## Risks

### Over-uniform panels

If implementation falls back to repeating one generic sub-card style inside every module, the dashboard will lose the distinctiveness validated during design.

### Hardcoded layout coupling

If the implementation bakes too much behavior directly into one large Home view, future swapping and resizing will become expensive.

### Count-heavy dashboard

If too much static information leaks into the main grid, the dashboard will feel like analytics instead of a vault command center. The telemetry strip exists to prevent this.

### Resizing-unaware internals

If panel internals are authored only for one exact size, future resizing support will require substantial rewrites.

## Rollout

Recommended implementation order:

1. Introduce dashboard shell and panel boundaries.
2. Add the telemetry strip.
3. Implement the `Overview`, `Needs Attention`, and `Vault Pulse` top row.
4. Implement differentiated middle-row panels.
5. Implement `Resurface` and `Pinned Projects`.
6. Polish spacing, visual hierarchy, and interaction targets.
7. Only after the fixed dashboard is solid, consider future settings for metric visibility or panel swapping.
