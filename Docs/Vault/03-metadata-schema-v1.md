# Metadata Schema v1

> How the agent knows what something is. Universal fields every item gets, plus kind-specific fields when relevant.

## Where Metadata Lives

- **Frontmatter** in `.md` files (lightweight, human-readable)
- **Sidecar `.json`** next to non-markdown files (weblocs, images, PDFs)
- **Existing indexes** in `.cider/` (backward compat — Cider app reads these)

Frontmatter is preferred for markdown files. Sidecar JSON is for everything else. Both are optional initially — the agent adds metadata when it has the information, not preemptively.

## Universal Fields

Every meaningful captured item should eventually have these:

```yaml
id: "uuid"                    # Cider's internal ID
kind: "place"                 # Object type (see allowed values)
title: "Dumpling World"       # Human-readable name
created_at: "2026-04-07"      # When captured
updated_at: "2026-04-07"      # Last modified
source: "https://..."         # Where it came from (URL, "imessage", "manual", "clipboard")
tags: [chinese, date-night]   # Cross-cutting descriptors
summary: "Chinese dumplings in Bellevue, WA"  # One-line for indexes
```

**Rules:**
- `id` — use existing Cider UUID if the item already has one. Generate with `uuidgen` for new items.
- `kind` — **required before an item is considered fully classified.** An item without a `kind` is still a `capture` and needs triage. See allowed values below.
- `title` — descriptive, not the source name. "Dumpling World" not "TikTok".
- `source` — the original URL, or how it arrived.
- `tags` — lowercase, hyphenated. Not duplicates of kind or folder name.
- `summary` — short enough to scan in an index. One sentence max.

## Allowed `kind` Values

| Kind | Meaning | When to Use |
|------|---------|-------------|
| `person` | Someone the user knows | Any accumulated knowledge about an individual |
| `project` | Active build or workstream | Something being actively worked on with artifacts |
| `topic` | Durable knowledge area | A subject that accumulates material over time (Streamio, 3D printing) |
| `procedure` | Repeatable how-to | Step-by-step guide, troubleshooting fix, setup instructions |
| `place` | Physical location | Restaurant, store, venue, doctor's office |
| `reference` | Saved link or article | A bookmark, saved video, product link, article |
| `capture` | Unclassified incoming item | Just arrived, not yet triaged. Temporary kind. |

**Rules:**
- `capture` is temporary and **must be upgraded** to a specific kind when enough context is available. An item should not remain `capture` across multiple sessions.
- A single item has exactly one `kind`. Not multiple.
- `kind` is metadata, not a folder name. A `place` can live in `Food/Restaurants/` or `Life/Medical/`.

## Kind-Specific Fields

### person

```yaml
kind: person
relationship: "girlfriend"     # friend, family, coworker, doctor, etc.
birthday: "1990-01-15"         # optional
```

### project

```yaml
kind: project
status: "active"               # active, paused, done
repo: "https://github.com/..." # optional
```

### topic

```yaml
kind: topic
domain: "tech"                 # which top-level folder domain
```

### procedure

```yaml
kind: procedure
related_topic: "streamio"      # what topic this procedure belongs to
last_verified: "2026-03-01"    # when the steps were last confirmed working
```

### place

```yaml
kind: place
subkind: "restaurant"          # restaurant, store, venue, park, office
city: "bellevue"
cuisine: "chinese"             # restaurants only
price_range: "$$"              # optional
address: "123 Main St"         # optional
```

### reference

```yaml
kind: reference
url: "https://..."
content_type: "article"        # article, video, product, social-post, tool
```

### capture

```yaml
kind: capture
raw_input: "user texted this"  # what was received before classification
```

## Tags

### What Tags Are For

- Cross-domain relationships: `date-night` spans Food and Life
- Filtering: "show me all `favorite` items"
- Discovery: "what else is tagged `seattle`?"
- Temporal context: `tiktok`, `from-ashley`

### What Tags Are NOT For

- Identity: don't tag something `restaurant` — that's `kind: place, subkind: restaurant`
- Folder replacement: don't tag `gaming` instead of filing in `Hobbies/Gaming/`
- Hierarchy: tags are flat. No tag nesting.

### Tag Format

- Lowercase
- Hyphenated for multi-word: `date-night`, `gift-idea`
- Short and reusable: prefer `seattle` over `seattle-wa-usa`
- Max ~5 tags per item. Don't over-tag.

## Sidecar JSON Example

For a bookmark `Food/Restaurants/Chinese/Dumpling World.webloc`:

```json
{
  "id": "a1b2c3d4-...",
  "kind": "place",
  "subkind": "restaurant",
  "title": "Dumpling World",
  "created_at": "2026-04-07T12:00:00Z",
  "updated_at": "2026-04-07T12:00:00Z",
  "source": "https://www.tiktok.com/@foodie/video/123",
  "tags": ["chinese", "date-night", "bellevue"],
  "summary": "Chinese dumplings and soup dumplings in Everett, WA",
  "city": "everett",
  "cuisine": "chinese",
  "price_range": "$$",
  "address": "620 SE Everett Mall Way #400, Everett, WA 98208",
  "hours": "Tue-Fri 11am-2:30pm & 5-8:30pm, Sat-Sun 11am-8:30pm, Closed Mon"
}
```

## Frontmatter Example

For a note `People/Ashley/profile.md`:

```markdown
---
id: b2c3d4e5-...
kind: person
title: Ashley
relationship: girlfriend
birthday: 1990-01-15
tags: [important]
summary: Girlfriend — preferences, sizes, gift ideas
---

## Basics

- Birthday: January 15
- Shoe size: 8.5

## Gift Ideas

- ...
```

## Index Files (Future)

These are not required for v1 but will be added:

- `CiderVault/.cider/indexes/master_index.json` — all items with kind, path, summary
- `Food/Restaurants/folder_index.json` — local summary of restaurants
- `People/folder_index.json` — local summary of people profiles
- `CiderVault/.cider/indexes/recent_activity.json` — last 50 captures with timestamps

Index files are derived from metadata — they are caches, not sources of truth.
