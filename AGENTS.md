# Cider Agent Notes

## Cider Development Kanban

Kanban is a first-class development workflow for Cider, not just an app feature.

Docs and Kanban have different jobs:

- Docs are Cider's durable foundation: product vision, architecture, data model, UX principles, agent operating rules, routing doctrine, QA procedures, and big feature designs that should remain true after an implementation card is done.
- Kanban is Cider's active work surface: small tweaks, bugs, follow-up ideas, implementation tasks, testing tasks, code review findings, and short handoff records.
- Promote important Kanban outcomes into docs when they become lasting product, architecture, UX, data-model, routing, QA, or agent-behavior decisions.
- Large implementation plans/specs may live under `Docs/superpowers/`, but active tracking should still live on a Kanban card. Link the card to the plan/spec, and promote only durable outcomes into Product, Architecture, Feature, Vault, QA, or Conventions docs.
- Do not create stray Markdown docs for every task. Use a full doc only when the work needs a durable standalone foundation record or large spec.

For Cider development work, agents should use the boards in `~/CiderVault/.cider/boards/` as the shared source of truth:

- For read-only audits or quick inspections, do not move or create Kanban cards unless the user asks.
- Check the relevant board before starting substantial work.
- If the work already has a card, move it to the active work column before implementing.
- If the work does not have a card, add one with a concise title, useful notes/spec context, and `created: 'YYYY-MM-DD'`.
- Move work through the board as reality changes: backlog/planned -> in_progress -> testing/ready to test -> done.
- For bugs, use the bugs board and move fixed items to `fixed`.
- Put implementation notes, test evidence, blockers, and follow-up context on the card instead of scattering one-off Markdown files unless a full spec/doc is genuinely needed.
- Use `Docs/QA/` for reusable audit procedures, release/regression plans, and historical reports that should remain useful after the card is done.
- When a Kanban card grows into multiple deliverables, create child cards linked to the parent instead of expanding one forever-card. Parent cards should summarize direction; child cards should carry scoped implementation notes, test evidence, commits, and status.
- Keep card text useful for future handoff to Hermes, Codex, or another agent.

Active board files:

- `~/CiderVault/.cider/boards/a1b2c3.yaml` — Cider Roadmap
- `~/CiderVault/.cider/boards/d4e5f6.yaml` — Cider Bugs
- `~/CiderVault/.cider/boards/p1l2m3.yaml` — Implementation Plans
- `~/CiderVault/.cider/boards/e7f8a9.yaml` — Kanban Implementation
- `~/CiderVault/.cider/boards/f0d730.yaml` — Vault Agent Work

YAML rules:

- Preserve board YAML structure and indentation.
- Every card must have a `created` field.
- Quote dates with single quotes, for example `created: '2026-05-03'`.
- Do not duplicate keys on a card.
- Prefer structured parsing or a whole-file rewrite over small indentation-sensitive YAML edits.

## Social Voice

For Cider social posts, write like a useful product made by a real person.

- Professional, but not corporate.
- Clear about what Cider does.
- Lightly humorous or mildly snarky when it fits.
- Specific examples beat vague productivity language.
- Avoid obvious AI phrasing, launch hype, and em dashes.
- Default vibe: helpful Mac app, tiny bit opinionated, never uptight.
