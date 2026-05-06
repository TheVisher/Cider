# Folder Domains v1

> This is the locked folder structure for the Cider vault. Do not invent new top-level folders. Do not store loose files directly in top-level folders — always use subfolders.

## Top-Level Structure

```
CiderVault/
  Inbox/          # Temporary holding. Agent triages out of here.
  People/         # Durable person profiles
  Projects/       # Active builds and workstreams
  Tech/           # Setup guides, troubleshooting, workflows, tools
  Food/           # Restaurants, recipes, grocery
  Hobbies/        # Gaming, 3D printing, wallpapers, design
  Life/           # Travel, shopping, household, medical, finance
  Media/          # Images, screenshots, PDFs, videos
```

## Rules

1. **Top-level folders are fixed.** Do not create new ones without explicit user approval.
2. **No loose files in top-level folders.** Always use a subfolder. `Life/random.md` is wrong. `Life/Medical/random.md` is right.
3. **Inbox is temporary.** Nothing should stay there long-term. The agent triages items out within one session when possible.
4. **Subfolders are flexible.** Create them as needed within the domains. The agent can create `Food/Restaurants/Thai/` without asking.
5. **Folder names are human-readable.** Use plain English, title case, no abbreviations. `3D Printing` not `3d-printing`.
6. **Single source of truth.** Each item has exactly one canonical location in the vault. Do not duplicate files across folders. Use metadata and tags for relationships.
7. **Life/ must always use subfolders.** Never store files directly in `Life/`. Always use `Life/Travel/`, `Life/Medical/`, etc.

## Domain Definitions

### Inbox

Temporary holding area for uncategorized captures. When the agent can't confidently classify something, it goes here. The agent should attempt to triage Inbox items into the correct domain whenever it has enough context.

Subfolders (pre-existing):
- `Bookmarks/` — uncategorized URLs
- `Notes/` — uncategorized text
- `Contacts/` — new contacts
- `Todos/` — new tasks
- `Date Cards/` — new events
- `Images/` — unsorted images
- `Videos/` — unsorted videos
- `Files/` — unsorted documents

### People

Persistent knowledge about individuals. One subfolder per person when they accumulate enough material. Lightweight contacts stay as single files.

Examples:
- `People/Ashley/` — profile, timeline, gift ideas, sizes
- `People/Mom/` — profile, medical notes, preferences
- `People/Dr. Chen.vcf` — simple contact, no subfolder needed yet

### Projects

Active builds and workstreams. One subfolder per project. Includes decisions, logs, artifacts.

Examples:
- `Projects/Cider/` — the app itself
- `Projects/WoW Addons/MyAddon/` — addon development
- `Projects/Home Office/` — desk setup, cable management

### Tech

Knowledge about systems, tools, setup, troubleshooting, and workflows. If it's about HOW something works or HOW to fix something → Tech. If you're BUILDING something → Projects. If you're just INTERESTED in it → Hobbies.

Examples:
- `Tech/Streaming/Streamio/` — setup, troubleshooting, fixes
- `Tech/Linux/` — commands, configs
- `Tech/3D Printing Software/` — slicer settings, firmware
- `Tech/macOS/` — workflows, defaults commands
- `Tech/Coding/` — language references, tools

### Food

Restaurants, recipes, grocery references, cooking notes. Separated from Hobbies because it's a high-volume domain.

Examples:
- `Food/Restaurants/Chinese/Dumpling World.md`
- `Food/Restaurants/Coffee/Storyville.md`
- `Food/Recipes/Chocolate Chip Cookies.md`
- `Food/Grocery/Costco Finds.md`

### Hobbies

Long-term personal interests and recreational domains.

Examples:
- `Hobbies/Gaming/WoW/` — guides, builds (not addon dev — that's Projects)
- `Hobbies/Gaming/` — gameplay guides, tabletop/D&D references, mods/addons for use, gaming hobby context
- `Hobbies/3D Printing/Prints/`
- `Hobbies/3D Printing/Materials/`
- `Hobbies/Wallpapers/`
- `Hobbies/Design Inspiration/`
- `Hobbies/Music/`

### Life

Practical personal operations. Day-to-day logistics, not hobbies or knowledge.

Subfolders (required — no loose files):
- `Life/Travel/` — trip ideas, itineraries, packing lists
- `Life/Shopping/` — product research, wishlists, size references
- `Life/Household/` — home maintenance, utilities, furniture
- `Life/Medical/` — appointments, prescriptions, health notes
- `Life/Finance/` — accounts, budgets, tax docs

### Media

Saved media files and watchlist/reference bookmarks where the media item itself is the primary object.

Examples:
- `Media/Screenshots/`
- `Media/Photos/`
- `Media/PDFs/`
- `Media/Videos/`
- `Media/Downloads/`
- `Media/Movies/` — movie watchlist/reference bookmarks
- `Media/TV Shows/` — TV watchlist/reference bookmarks
- `Media/Games/` — game store pages, Steam links, demos/playtests, game watchlist/reference bookmarks

## Disambiguation Guide

| If it's... | It goes in... | Not in... |
|------------|---------------|-----------|
| A restaurant you want to remember | `Food/Restaurants/` | `Life/` |
| A recipe you want to cook | `Food/Recipes/` | `Hobbies/` |
| How to set up software | `Tech/` | `Projects/` |
| Building an addon or app | `Projects/` | `Tech/` or `Hobbies/` |
| Game store/watchlist page, Steam game, demo, or playtest | `Media/Games/` | `Life/Shopping/` |
| Gameplay guide, tabletop/D&D reference, mod/addon for use | `Hobbies/Gaming/` | `Projects/` |
| A product you're researching | `Life/Shopping/` | `Tech/` |
| A person's birthday or size | `People/` | `Life/` |
| A trip you're planning | `Life/Travel/` | `Hobbies/` |
| A screenshot for reference | `Media/Screenshots/` | `Tech/` |
| A PDF manual for a printer | `Tech/3D Printing Software/` or `Hobbies/3D Printing/` | `Media/PDFs/` |

## Coexistence with Current Structure

The existing user folders on disk (`Applications`, `Development`, `Fun & Social`, `Gaming`, `Products`, `Recipes`, `Restaurants`, `Trip ideas`, `Wallpapers`) continue to work. Cider reads them as-is. The new structure is introduced gradually — the agent routes new items into the new domains. Existing folders are migrated when the user explicitly approves.
