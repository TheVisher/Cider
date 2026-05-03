# Dashboard Product Behavior

**Status:** Durable product source of truth for the Dashboard feature.

---

## North Star

Dashboard should feel like a living, local-first second brain that watches Erik's own context and brings the right thing forward at the right time.

It is not a generic feed. It is:

```text
personal context resurfacing + curated discovery + action routing
```

---

## What Good Cards Answer

Every useful card should answer:

```text
What happened?
Why does this matter to me?
What vault item, taste signal, reminder, project, or interest caused this to appear?
What can I do with it?
Should Cider remember my reaction?
```

`whyItMatters` is required as a product concept even if the field is optional in the MVP schema.

---

## Core Lanes

### Main

The existing overview dashboard remains the `Main` view. It is orientation: what is going on in the vault right now?

### Sports

- Seahawks roster/season updates that actually matter
- Mariners games, standings shifts, ceremonies, injuries, trades/signings
- time-sensitive watch cards when timing matters

### Games

- updates for games Erik saved, wishlisted, played, or reacted to
- similar co-op, survival, MMO, strategy, or interesting indie games
- Steam playtests, release dates, demos, major patches

### Movies / TV / Entertainment

- sequel, trailer, adaptation, renewal/cancellation, and release-date updates
- watchlist-driven recommendations
- co-watch suggestions tuned to shared tastes

### Cider Projects

- active plan status
- stale docs or doc rot
- recent agent runs
- bugs needing review
- next-best-action cards

### Vault Curation

- recent captures needing routing
- generic bookmarks needing title cleanup
- notes with obvious follow-up tasks
- duplicates, stale todos, forgotten events, unfinished ideas

---

## Card Quality Rules

Show a card when it is at least one of:

- timely
- personal
- actionable
- resurfacing
- discovery
- maintenance

Do not show cards that are generic, unsourced, repetitive, low-context, or unable to explain why they matched Erik.

---

## Actions

MVP actions:

- open source URL
- mark seen
- dismiss
- rate 1-5
- more like this
- less like this

Future actions:

- save as bookmark
- save as note / memory
- create todo
- create event
- create reminder
- snooze
- ask AI
- mark stale / wrong / not relevant

---

## Design Personality

The Dashboard should feel like a calm command center, not a noisy content feed.

Useful adjectives:

- focused
- explainable
- visual
- personal
- actionable
- not overwhelming

---

## Non-Goals

- Do not become a generic RSS/news feed.
- Do not replace full search, calendar, or assistant experiences.
- Do not hide why something appeared.
- Do not add AI/news collectors until the card/action loop is useful.
- Do not sync to Web before the schema gate.
