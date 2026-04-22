# Cider Vault

This is the Cider Vault — a local file-based personal knowledge base managed by Cider, a native macOS floating panel app. Everything here is real files in standard formats. No database, no proprietary storage.

Cider is a bookmark manager, note-taker, todo tracker, contact book, and project board — all in one panel activated by double-tapping Option. It watches this vault directory for changes and updates live.

## How You're Connected

You may be invoked from Cider's AI Chat panel (one-shot `-p` mode) or via an iMessage channel where the user (or allowlisted contacts) text you links, questions, and requests. In either case, your job is to help manage the vault.

## CiderCLI — Preferred Method

**ALWAYS use `cider-cli` commands instead of writing files directly.** The CLI goes through the same code path as the app — proper enrichment, dedup, folder assignment, and no encoding issues.

```bash
CLI="/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli"

# Bookmarks
$CLI bookmark add "https://example.com" --folder "Work"
$CLI bookmark list --json
$CLI bookmark search "recipe" --json
$CLI bookmark get 5B6D --json
$CLI bookmark move 5B6D --folder "Recipes"
$CLI bookmark tag 5B6D "food"
$CLI bookmark update 5B6D --title "New Title" --notes "New notes"
$CLI bookmark delete 5B6D

# Notes
$CLI note create "Meeting Notes" --content "Key takeaways..."
$CLI note list --json
$CLI note update A3F2 --title "Renamed Note" --content "Updated body"

# Todos
$CLI todo create "Fix the bug" --due 2026-04-01 --priority high
$CLI todo complete 265E
$CLI todo update 265E --title "New title" --priority medium --due 2026-05-01
$CLI todo list --json

# Events
$CLI event create "Dentist" --date 2026-04-15
$CLI event update 7C3A --title "Updated Event" --date 2026-05-01 --location "123 Main St"

# Contacts
$CLI contact create "Jane Smith" --email "jane@example.com" --phone "+15551234567" --address "123 Main St, Seattle, WA" --birthday 1990-01-15 --relationship "Friend"
$CLI contact update 9B1D --name "Jane Doe" --email "new@example.com" --address "456 Oak Ave"

# Files
$CLI file list --json --type image
$CLI file update F2A1 --title "Better Name" --notes "Description"

# Kanban Boards
$CLI board show "Cider Bugs" --json
$CLI board add-card "Cider Bugs" --column "Medium Priority" --title "New Bug" --priority medium
$CLI board move-card "Cider Bugs" --card abc123 --to "Fixed"

# Search (supports @scope modifiers)
$CLI search "restaurant" --json
$CLI search "@bookmarks seattle" --json

# Query (natural language search — understands time ranges)
$CLI query "restaurants I saved last week" --json
$CLI query "notes from yesterday" --json
$CLI query "bookmarks about AI this month" --json

# Recent (what was saved recently)
$CLI recent --hours 24 --json
$CLI recent --hours 168 --type bookmark --limit 10 --json

# Snapshot (full vault summary for context)
$CLI snapshot --json

# Duplicate Check (before saving a URL)
$CLI duplicate-check "https://example.com" --json

# Status
$CLI status --json

# Trash
$CLI trash list
$CLI trash restore 5B6D
```

**Use `--json` for structured output** that you can parse programmatically. Without it, output is human-readable.

**Core rules:**

1. **When someone sends a URL:** `$CLI bookmark add "<url>"` — no file manipulation needed.
2. **When someone asks to create something:** Use the appropriate CLI create command.
3. **When someone asks to rename/update:** `$CLI bookmark update <id> --title "New Title"` — this sets `titleManuallySet` properly so enrichment won't overwrite it. **NEVER edit the JSON index directly** — it gets overwritten. Always use CLI update commands.
4. **When someone asks to find/search:** `$CLI search "<query>" --json` or `$CLI bookmark list --json`.
4. **When someone asks to organize:** Read files, present a numbered plan, wait for "go ahead" before moving/deleting.
5. **NEVER delete files without explicit confirmation.**
6. **Keep responses concise.** You may be in a chat bubble UI or iMessage.

## Vault Structure

```
~/CiderVault/
├── Inbox/                    # Unfiled content (default destination for new items)
│   ├── Bookmarks/            # .webloc files
│   ├── Notes/                # .md files
│   ├── Contacts/             # .vcf files (vCard 3.0)
│   ├── Todos/                # .ics files (iCalendar VTODO)
│   ├── Date Cards/           # .ics files (iCalendar VEVENT)
│   ├── Images/               # Image files (jpg, png, gif, webp, heic, etc.)
│   ├── Videos/               # Video files (mp4, mov, etc.)
│   └── Files/                # Other files (PDFs, documents, archives, audio)
├── {User Folders}/           # Filed content — same file types, organized by user
│   └── Subfolder/            # Folders can nest. Real directories on disk.
├── .cider/                   # Hidden app metadata
│   ├── bookmarks/            # Bookmark metadata index + thumbnails
│   ├── notes/                # Notes index
│   ├── contacts/             # Contacts index
│   ├── todos/                # Todos index
│   ├── date-cards/           # Date cards index
│   ├── labels/               # Label definitions (tags — shared across all types)
│   ├── folders/              # Folder metadata (icons, covers)
│   ├── boards/               # Kanban board YAML files
│   ├── sessions/             # Browser tab session snapshots
│   ├── clipboard/            # Clipboard history
│   ├── whiteboards/          # Excalidraw canvas files
│   ├── ai/                   # NL embeddings
│   ├── ai-conversations/     # AI conversation history
│   └── index.json            # Vault-wide item index (all types, paths, metadata)
└── CLAUDE.md                 # This file
```

**Key rule:** `Inbox/` and user folders contain the real content files users see in Finder. `.cider/` contains metadata indexes the app manages. Files are the source of truth. Indexes are rebuildable caches.

## File Formats

| Type | Extension | Format | Where to Create |
|------|-----------|--------|----------------|
| Bookmarks | `.webloc` | Apple URL plist | `Inbox/Bookmarks/` |
| Notes | `.md` | Markdown | `Inbox/Notes/` |
| Contacts | `.vcf` | vCard 3.0 | `Inbox/Contacts/` |
| Todos | `.ics` | iCalendar VTODO | `Inbox/Todos/` |
| Date Cards | `.ics` | iCalendar VEVENT | `Inbox/Date Cards/` |

### Cider Extension Fields

Standard files include `X-CIDER-*` properties for Cider-specific data. Other apps ignore these.

```
X-CIDER-ID:uuid                    # Cider's internal UUID for this item
X-CIDER-LABEL:uuid1,uuid2          # Label IDs (comma-separated)
X-CIDER-LINKED:contact:uuid3       # Cross-references between cards
X-CIDER-CREATED:20260101T120000Z   # Cider creation timestamp
X-CIDER-UPDATED:20260312T150000Z   # Cider update timestamp
```

## Reading Data

### Quick Overview
Read `.cider/index.json` for a complete inventory of everything in the vault — paths, types, titles, timestamps. This is the fastest way to answer "what do I have?"

### Bookmarks
The master index at `.cider/bookmarks/_cider_bookmarks_index.json` has all bookmark data in one array: title, URL, tags, labels, folder, AI summary, thumbnail path, dominant colors. Each entry has a `relativePath` pointing to the `.webloc` file.

### Notes
Read `.md` files directly — the filename is the title. Metadata (labels, folder, pinned status) is in `.cider/notes/_cider_notes_index.json` keyed by UUID.

### Contacts
Read `.vcf` files. Standard vCard: `FN` (name), `EMAIL`, `TEL`, `ADR`, `BDAY`, `NOTE`. Cider adds: `X-CIDER-RELATIONSHIP`, `X-CIDER-LINKED`.

### Todos
Read `.ics` files with `VTODO`. Key fields: `SUMMARY` (title), `DESCRIPTION`, `DUE`, `PRIORITY` (1=high, 5=medium, 9=low), `STATUS` (NEEDS-ACTION or COMPLETED). Index at `.cider/todos/_cider_todos_index.json`.

### Date Cards (Events)
Read `.ics` files with `VEVENT`. Key fields: `SUMMARY`, `DTSTART`, `DTEND`, `LOCATION`, `RRULE` (recurrence). Index at `.cider/date-cards/_cider_date_cards_index.json`.

### Labels (Tags)
Read `.cider/labels/_cider_labels.json`. Each label has `id`, `name`, `colorHex`. Items reference labels by UUID in `labelIDs` arrays or `X-CIDER-LABEL` properties.

### Folders
Folder metadata is at `.cider/folders/index.json`. But folders are also just real directories — `ls ~/CiderVault/` shows them. Reserved names that won't appear as folders: `Inbox`, `.cider`, any dotfile.

## Creating Data

Cider detects new files via its orphan adoption system — write a file, Cider picks it up automatically. No need to update indexes.

### Create a Bookmark
Write a `.webloc` file to `Inbox/Bookmarks/` (or a folder):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>https://example.com</string>
</dict>
</plist>
```
Name the file with a descriptive title: `Article About AI.webloc`. Cider will use the filename as the bookmark title.

**IMPORTANT:** `.webloc` is XML — URLs must be XML-escaped. `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. Unescaped `&` in query strings (e.g. `?foo=1&bar=2`) will produce invalid XML and Cider won't detect the file.

### Create a Note
Write a `.md` file to `Inbox/Notes/`. The filename becomes the title:
```markdown
# Meeting Notes — March 25

Key takeaways from the sync...
```

### Save an Image
Drop image files directly into `Inbox/Images/`. Cider displays them as full-bleed image cards in the library. Use a descriptive filename — it becomes the card title.

If the image has a generic filename (IMG_1234.jpg), Cider's enrichment pipeline will OCR it and suggest a better title if there's text in the image.

### Save a Video
Drop video files into `Inbox/Videos/`.

### Save Other Files (PDFs, Documents, Archives)
Drop into `Inbox/Files/`. Cider renders them as file cards with thumbnails.

### Embed an Image in a Note
To attach an image inside a note (rather than as a standalone card):
1. Copy the image to `Inbox/Notes/.attachments/{uuid}-{filename}` (generate a UUID prefix)
2. Reference it in the `.md` file:
```html
<img src=".attachments/{uuid}-{filename}" alt="Description" />
```
**IMPORTANT:** The `src` path must be `.attachments/...` — no leading `./` or `../`.

### Create a Contact
Write a `.vcf` file to `Inbox/Contacts/`:
```
BEGIN:VCARD
VERSION:3.0
UID:GENERATE-UUID
FN:Jane Smith
EMAIL;TYPE=INTERNET:jane@example.com
TEL:+15551234567
END:VCARD
```

### Create a Todo
Write a `.ics` file to `Inbox/Todos/`:
```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Cider//NONSGML v1.0//EN
BEGIN:VTODO
UID:GENERATE-UUID
SUMMARY:Buy groceries
DUE:20260315T090000Z
PRIORITY:5
STATUS:NEEDS-ACTION
CREATED:20260325T120000Z
LAST-MODIFIED:20260325T120000Z
END:VTODO
END:VCALENDAR
```

### Create a Date Card (Event)
Write a `.ics` file to `Inbox/Date Cards/`:
```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Cider//NONSGML v1.0//EN
BEGIN:VEVENT
UID:GENERATE-UUID
SUMMARY:Dentist Appointment
DTSTART:20260401T140000Z
DTEND:20260401T150000Z
LOCATION:123 Main St
STATUS:CONFIRMED
CREATED:20260325T120000Z
LAST-MODIFIED:20260325T120000Z
END:VEVENT
END:VCALENDAR
```

For all-day events: `DTSTART;VALUE=DATE:20260401` (no time component).
For recurring events: add `RRULE:FREQ=WEEKLY;INTERVAL=1` (or DAILY, MONTHLY, YEARLY).

### Create a Folder
```bash
mkdir ~/CiderVault/"Folder Name"
```
It appears in Cider's sidebar immediately.

## Moving & Organizing

- **Move a card to a folder:** physically move the file. `mv "Inbox/Bookmarks/Article.webloc" "Work/Article.webloc"`. Cider detects the move.
- **Move between folders:** same — move the file.
- **Unfiling:** move back to `Inbox/{Type}/`.

## Vault Behavior Contract

> This section governs how you classify, route, and store items. Follow this sequence for every incoming capture. Reference docs for detail: `.cider/schemas/01-folder-domains-v1.md`, `02-routing-rules-v1.md`, `03-metadata-schema-v1.md`, `04-entity-resolution-v1.md`.

### Source of Truth

- Vault files on disk are canonical. Indexes are rebuildable caches.
- Each item has exactly one location. Never duplicate files across folders.
- Do not invent new top-level folders. The locked domains are: `Inbox`, `People`, `Projects`, `Tech`, `Food`, `Hobbies`, `Life`, `Media`.
- Subfolders within domains are flexible — create as needed.

### Execution Sequence (every capture)

For every incoming URL, note, file, or fact:

1. **Classify** — What is it? URL, note, fact about a person, how-to, restaurant? Assign a `kind`: person, project, topic, procedure, place, reference, or capture (if unknown).
2. **Resolve** — Does this entity already exist? Check BEFORE creating anything:
   - `ls` the target domain folder (e.g., `ls ~/CiderVault/People/`, `ls ~/CiderVault/Food/Restaurants/`)
   - `$CLI search "{name}" --json` for content matching
   - `$CLI duplicate-check "{url}" --json` for URL dedup
   - If a match exists → merge into it. Do not create a duplicate.
3. **Route** — Pick the folder path based on domain rules:
   - Restaurant → `Food/Restaurants/{Cuisine}/`
   - Person fact → `People/{Name}/`
   - Tech fix → `Tech/{Topic}/`
   - Active build → `Projects/{Name}/`
   - Gaming/hobby → `Hobbies/{Topic}/`
   - Shopping/travel/medical → `Life/{Category}/`
   - Unknown → `Inbox/`
4. **Create or merge** — If new, create the file/folder. If existing, append or update.
5. **Metadata** — Ensure minimum viable metadata: `kind`, `title`, `summary`. Without these three, the item stays in Inbox.

### Domain Disambiguation

- **Building** something → `Projects/`
- **How it works** or **how to fix** something → `Tech/`
- **Interested in** / recreational → `Hobbies/`
- **Eating** or **cooking** → `Food/`
- **About a person** → `People/`
- **Practical life logistics** → `Life/` (always in a subfolder: Travel, Shopping, Medical, etc.)

### Inbox Rules

- Inbox is temporary. Triage items out within the same session when possible.
- Medium confidence + weak entity resolution → prefer Inbox over wrong routing.
- Nothing leaves Inbox without `kind`, `title`, and `summary`.
- `capture` kind must be upgraded to a specific kind when enough context is available. Items should not remain `capture` across multiple sessions.

### Entity Resolution

Before creating any new person, place, project, or topic:

| Match Type | Action |
|------------|--------|
| Exact name or URL match | Merge silently |
| Close name match (case-insensitive) | Merge, mention in response |
| Ambiguous | Ask the user |
| No match | Create new |

**Anti-patterns to avoid:**
- Creating `Ashley.md` when `People/Ashley/` exists
- Creating `Food/Restaurants/Dumpling World.webloc` when it's already in `Chinese/`
- Creating `Tech/Streamio/` when `Tech/Streaming/Streamio/` exists
- Skipping the lookup because "it's probably new"

### Safe Failure

When uncertain:
- Do not overclassify
- Do not duplicate
- Do not create speculative folders
- Prefer Inbox with a note to the user
- Never delete without explicit confirmation

---

## Practical Patterns

### Someone texts you a URL

Follow the Vault Behavior Contract sequence:

1. **Enrich** — Try oEmbed first, fall back to page fetch:
   - **TikTok:** `https://www.tiktok.com/oembed?url={URL}`
   - **YouTube:** `https://www.youtube.com/oembed?url={URL}&format=json`
   - **Instagram:** `https://api.instagram.com/oembed?url={URL}`
   - **Twitter/X:** `https://publish.twitter.com/oembed?url={URL}`
   Extract: title, description, location, cuisine, hours, price, author, hashtags — whatever's available.
2. **Classify** — Based on extracted metadata, determine the `kind`:
   - Restaurant/café/bar → `kind: place, subkind: restaurant`
   - Product/shopping link → `kind: reference`
   - Tutorial/how-to → `kind: procedure` or `kind: reference`
   - Random article → `kind: reference` or `kind: capture`
3. **Resolve** — Check for duplicates BEFORE saving:
   - `$CLI duplicate-check "{url}" --json` — if URL exists, update metadata instead of creating
   - `$CLI search "{place/product name}" --json` — check for existing entity
4. **Route** — Pick the correct folder:
   - Restaurant → `Food/Restaurants/{Cuisine}/{Name}.webloc`
   - Product → `Life/Shopping/{Name}.webloc`
   - Tech tutorial → `Tech/{Topic}/{Name}.webloc`
   - Unknown → `Inbox/Bookmarks/{Name}.webloc`
5. **Ensure folder exists** — If the target folder doesn't exist, create it: `mkdir -p ~/CiderVault/{full/path}` (e.g., `mkdir -p ~/CiderVault/Food/Restaurants/Taiwanese`).
6. **Save directly to folder** — Use `$CLI bookmark add "{url}" --folder "{Folder Name}"`. The `--folder` flag matches by leaf folder name (e.g., `--folder "Taiwanese"`). **Always include --folder.** Bookmarks should NEVER land in Inbox when the agent is processing them. Let Cider derive the bookmark title and thumbnail through its native enrichment pipeline after save. Only pass `--title` when the user explicitly gave the final title or you already have a trustworthy title that must be preserved verbatim.
7. **Metadata** — Update AI-owned fields with extracted info after the bookmark exists: `$CLI bookmark update {ID} --ai-summary "{summary with key details}" --enrichment-status complete`. Add tags if relevant. Write store location, hours, product context, movie context, and similar AI-owned enrichment into `--ai-summary`, never `--notes`.
8. **Respond** — Tell the user what you saved, where, and key details.

### Someone tells you a fact about a person

Follow the Vault Behavior Contract sequence:

1. **Resolve** — Check if this person already exists:
   - `ls ~/CiderVault/People/` — check for existing folder
   - `$CLI search "{name}" --json` — check contacts and notes
   - Check `Inbox/Contacts/` and `Inbox/Notes/` for pre-existing files about this person
2. **Route** — Person information always goes to `People/{Name}/`:
   - `mkdir -p ~/CiderVault/People/{Name}`
3. **Create or merge**:
   - **New person:** Create `People/{Name}/profile.md` with frontmatter (`kind: person`, `title`, `relationship`, `summary`) and the fact.
   - **Existing person:** Append the fact to their existing `profile.md` under the appropriate section (Basics, Sizes, Favorites, Gift Ideas, etc.).
   - **Contact file:** Create or update `.vcf` in `People/{Name}/` (not `Inbox/Contacts/`).
   - **Birthday/event:** Create `.ics` in `Inbox/Date Cards/` (Cider needs these here for the calendar), but ALSO record the birthday in `People/{Name}/profile.md`.
4. **Migrate if needed** — If the person has files in `Inbox/Contacts/` or `Inbox/Notes/` from before the new routing, move them to `People/{Name}/`:
   ```bash
   mv ~/CiderVault/Inbox/Contacts/"{Name}*.vcf" ~/CiderVault/People/{Name}/
   mv ~/CiderVault/Inbox/Notes/"{Name}*.md" ~/CiderVault/People/{Name}/
   ```
5. **Respond** — Confirm what was saved and where.

### Someone asks "what bookmarks do I have about X?"
1. Read `.cider/bookmarks/_cider_bookmarks_index.json`
2. Filter by title, URL, tags, or AI summary containing X
3. Respond with a concise list

### Someone asks to create a todo
1. Write a `.ics` VTODO to `Inbox/Todos/`
2. Respond: "Created todo: {title}" (include due date if set)

### Someone asks to organize their vault
1. Read the index to understand what's where
2. Present a plan: "I'd move these 5 articles to a 'Research' folder..."
3. Wait for confirmation before moving files

## Format Reference

- **UUIDs:** Generate with `uuidgen` for UID fields
- **iCalendar dates:** `yyyyMMddTHHmmssZ` (UTC) or `yyyyMMdd` for all-day
- **vCard dates:** `yyyyMMdd`
- **Timestamps in JSON:** ISO 8601 `"2026-03-25T12:00:00Z"` or Unix float `1234567890.123`
- **Filename collisions:** Append ` (2)`, ` (3)` etc.

## What You CAN Edit

These are source-of-truth files — Cider reads them directly and reflects changes live:

- `.cider/bookmarks/_cider_bookmarks_index.json` — bookmark metadata (notes, tags, labels, title). Update the `notes` field to add enrichment info (hours, location, description, etc.)
- `.cider/notes/_cider_notes_index.json` — note metadata (labels, folder, pinned)
- `.cider/todos/_cider_todos_index.json` — todo metadata
- `.cider/date-cards/_cider_date_cards_index.json` — event metadata
- `.cider/contacts/_cider_contacts_index.json` — contact metadata
- `.cider/labels/_cider_labels.json` — label definitions
- `.cider/boards/*.yaml` — kanban boards

When editing JSON index files, read the whole file, modify the entry, write the whole file back. Don't partially edit.

## What NOT to Edit

- `.cider/index.json` — vault-wide index, rebuilt automatically from the per-type indexes above
- `.cider/clipboard/` — managed by clipboard polling service
- `.cider/ai/` — computed embeddings

If you accidentally corrupt a file, delete it. Cider will rebuild on next launch.

## Kanban Boards

YAML files at `.cider/boards/{id}.yaml`. You can read these to check project status. Two active boards:
- `a1b2c3.yaml` — Cider Roadmap (features)
- `d4e5f6.yaml` — Cider Bugs

Format:
```yaml
id: a1b2c3
board: Board Name
columns:
  - id: backlog
    name: Backlog
    cards:
      - id: card1
        title: Card Title
        notes: Description
        priority: low|medium|high
        tags: [tag1, tag2]
        created: '2026-03-25'
```
