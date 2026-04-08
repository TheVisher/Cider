# Entity Resolution Rules v1

> Before creating anything, the agent must check what already exists. This prevents duplicates, the single most corrosive failure mode in a personal memory system.

## Core Rule

**Never create a new entity without first checking for an existing match.**

This applies to: people, projects, topics, places, and any item that could be a duplicate of something already in the vault.

## Lookup Process

Before creating a new item, the agent follows this sequence:

### Step 1: Check the domain folder

```bash
ls ~/CiderVault/People/          # Does this person already have a folder?
ls ~/CiderVault/Projects/        # Does this project already exist?
ls ~/CiderVault/Food/Restaurants/ # Is this restaurant already saved?
ls ~/CiderVault/Tech/            # Does this topic already have a home?
```

This is fast — just a directory listing. The folder name IS the entity name.

### Step 2: Search via CLI

```bash
$CLI search "dumpling world" --json
$CLI duplicate-check "https://example.com" --json
```

This catches items that exist but might be in a different folder or have a slightly different name.

### Step 3: Check the vault index

```bash
$CLI snapshot --json | grep -i "ashley"
```

Or read `.cider/bookmarks/_cider_bookmarks_index.json` directly for URL matching.

## Match Types

| Match Type | Action |
|------------|--------|
| **Exact name match** | Merge into existing entity. No new file/folder. |
| **URL match** | Duplicate. Do not create. Update existing if needed. |
| **Close name match** (e.g., "Dumpling World" vs "dumpling world restaurant") | Treat as same entity. Merge. |
| **Same person, different context** (e.g., "Ashley" mentioned in a note vs `People/Ashley/`) | Add to existing person folder. |
| **Ambiguous** | Ask the user: "Is this the same as X?" |
| **No match found** | Create new entity. |

## Match Confidence

| Confidence | Evidence | Action |
|------------|----------|--------|
| **Certain** | Same URL, or exact folder name match | Merge silently |
| **High** | Same name (case-insensitive), same domain | Merge, mention in response |
| **Medium** | Similar name, same city/topic | Ask user before merging |
| **Low** | Vaguely related but unclear | Create new, note the possible relationship |

## Entity-Specific Rules

### People

Before creating `People/{Name}/`:
1. `ls ~/CiderVault/People/` — check for existing folder
2. Search contacts: `$CLI search "{name}" --json`
3. If the person exists, **always add to their existing folder**. Never create a second one.
4. Name normalization: "Ashley", "ashley", "Ash" → same person if context confirms it

### Places (Restaurants, Stores, etc.)

Before creating a restaurant file:
1. `ls ~/CiderVault/Food/Restaurants/` — check all cuisine subfolders
2. `$CLI duplicate-check "{url}" --json` — check URL
3. `$CLI search "{restaurant name}" --json` — check name
4. If the URL already exists, update the existing bookmark's metadata instead of creating a duplicate

### Projects

Before creating `Projects/{Name}/`:
1. `ls ~/CiderVault/Projects/` — check existing projects
2. If a project exists with a similar name, confirm with user before creating a new one

### Topics (Tech, Hobbies)

Before creating a new topic folder:
1. Check the relevant domain: `ls ~/CiderVault/Tech/` or `ls ~/CiderVault/Hobbies/`
2. A topic about "Streamio buffering" belongs in existing `Tech/Streaming/Streamio/`, not a new folder

## When To Create New

The agent may create a new entity when ALL of these are true:
1. Domain folder was checked — no matching folder exists
2. CLI search was run — no matching items found
3. The item is clearly distinct from everything in the vault

## When To Leave In Inbox

If the agent:
- Cannot determine the entity type with reasonable confidence
- Cannot find a clear domain match
- Suspects a match but isn't sure

Then: **leave in Inbox** and tell the user. Do not guess.

## Anti-Patterns

| Anti-Pattern | Why It's Bad | What To Do Instead |
|--------------|-------------|-------------------|
| Creating `Ashley.md` when `People/Ashley/` exists | Duplicate person | Add to existing folder |
| Creating `Food/Restaurants/Dumpling World.webloc` when it's already in `Food/Restaurants/Chinese/` | Duplicate place | Update existing file |
| Creating `Tech/Streamio/` when `Tech/Streaming/Streamio/` exists | Duplicate topic, different path | Use existing path |
| Creating `Projects/Cider App/` when `Projects/Cider/` exists | Duplicate project, name variant | Use existing folder |
| Skipping the lookup because "it's probably new" | Eventual duplicate chaos | Always check first |

## Implementation Notes

For v1, the lookup process uses:
- `ls` / `find` for folder checks (fast, no dependencies)
- `$CLI search` for content matching
- `$CLI duplicate-check` for URL dedup
- `.cider/bookmarks/_cider_bookmarks_index.json` for direct URL lookup

Future versions may add:
- Dedicated entity index files per domain
- Fuzzy name matching
- Embedding-based similarity search
