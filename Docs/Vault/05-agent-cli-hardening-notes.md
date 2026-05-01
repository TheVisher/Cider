# Agent CLI Hardening Notes

> Field notes from real Telegram/Cider agent sessions. Use this document to turn fragile agent habits into deterministic CLI behavior so weaker or local models can still operate Cider safely.

## Purpose

Cider's CLI should eventually encode the operational rules that a careful vault-native agent currently has to remember:

- save messy chat inputs reliably
- avoid duplicates before creating anything
- let Cider perform metadata/enrichment where possible
- propagate enriched titles and summaries into the item before reporting success
- route to the correct vault domain/folder instead of dumping obvious items in Inbox
- leave uncertain items in the correct type-specific Inbox subfolder
- report back the final verified title, folder, and caveats

The target design is that an AI model can be fairly simple: it should call a high-level CLI workflow and receive structured, verified facts rather than improvising path rules, metadata lookups, and post-save verification.

## Observed Edge Cases

### 1. Bare `Inbox` is not the same as `Inbox/Bookmarks`

A bookmark saved or moved to bare `Inbox` can exist as a webloc at a path like:

```text
Inbox/Tiktok.Com.webloc
```

That may not appear where the user expects in the app's Inbox bookmark section. For unresolved bookmark captures, use:

```text
Inbox/Bookmarks/{Title}.webloc
```

Example failure:

- TikTok metadata only exposed `#fyp` and the author `Jordan_The_Stallion8`.
- The agent left the item in bare `Inbox`.
- The user could not find it in Inbox.
- Moving it to `Inbox/Bookmarks` fixed visibility and produced a title-based filename:
  - `Inbox/Bookmarks/Jordan_The_Stallion8 TikTok.webloc`

CLI hardening ideas:

- `bookmark add --path Inbox` should either reject ambiguous bare Inbox for bookmarks or normalize it to `Inbox/Bookmarks`.
- `bookmark move <id> --path Inbox` should do the same normalization for bookmark items.
- `bookmark get --json` should expose both logical folder and exact relative path clearly.
- Add a warning field if a bookmark lives in a non-bookmark Inbox location.

### 2. Opaque short links need a post-save enrichment pass

TikTok short URLs, Instagram links, YouTube Shorts, X/Twitter posts, Reddit redirects, and similar links often start as host-only titles:

```text
Tiktok.Com
X.Com
Reddit.Com
```

A correct capture flow is:

1. `duplicate-check <url> --json`
2. `bookmark add <url> --path Inbox/Bookmarks` or another conservative staging path
3. re-read the bookmark by ID with `bookmark get <id> --json`
4. let Cider/provider metadata populate whatever it can
5. if still generic, use safe provider metadata such as oEmbed
6. update title if metadata reveals a canonical subject
7. route/move based on the revealed content
8. re-read and report final verified state

CLI hardening ideas:

- Add a single command such as `bookmark capture <url> --json --auto-route --enrich --verify`.
- Return a structured state machine: `duplicate | created | enriched | titleUpdated | moved | needsTriage`.
- Include `originalUrl`, `resolvedUrl`, `canonicalUrl`, `providerTitle`, `finalTitle`, `finalPath`, and `confidence`.
- Support `--wait-for-enrichment` or make enrichment synchronous for this workflow.
- Include `metadataSource` fields such as `cider-fetch`, `tiktok-oembed`, `twitter-oembed`, `opengraph`, or `manual-agent`.

### 3. Clean titles should replace host-only filenames

When metadata reveals a subject, host-only titles and filenames are poor UX. The agent should not leave items named `Tiktok.Com` when it has enough information to name them.

Examples from a batch save:

- `Churro cheesecake recipe — Jose el Cook` → `Food/Recipes`
- `Easy refried beans recipe — Annette Freckles` → `Food/Recipes`
- `Exit 5 Korean BBQ in Renton — Seattle Foodie` → `Food/Restaurants/Renton`
- `HeyGen HyperFrames Codex plugin announcement` → `Tech/AI`
- `Laundry basket organizer product — JyL_encuentras` → `Life/Household Stuff`
- `Cartel Pilots Wanted co-op smuggling game — Indie Game Joe` → `Hobbies/Gaming`
- `3D printed chopstick hack — NK3DLab` → `Hobbies/3D Printing`
- `Banana bread cinnamon rolls recipe — Annika Eats` → `Food/Recipes`

CLI hardening ideas:

- Provide `bookmark update --title` as an explicit, safe mutation and ensure it renames the backing webloc when appropriate.
- Provide `titleQuality` in JSON: `host-only`, `provider-generic`, `provider-useful`, `agent-cleaned`, `user-set`.
- Prefer a clean title for filename generation after enrichment.
- Do not overwrite `titleManuallySet == true` unless the user explicitly asks.

### 4. Duplicate detection should understand short-link identity

Short links can point to a canonical provider URL. Duplicate checks should not only compare the exact input URL.

CLI hardening ideas:

- Duplicate check should compare:
  - exact URL
  - normalized URL without tracking params
  - resolved final URL
  - provider canonical URL from oEmbed/OpenGraph
  - platform content ID such as TikTok `embed_product_id` or X/Twitter status ID
- Return duplicate candidates with `matchReason` and confidence.
- If a duplicate exists under a generic title, offer a safe path to enrich/retitle the existing item instead of creating another one.

### 5. Routing should use current vault topology, not stale doctrine

There is a documentation/codebase mismatch to resolve: older routing notes mention restaurant cuisine folders, while the current vault structure uses city folders such as:

```text
Food/Restaurants/Seattle
Food/Restaurants/Everett
Food/Restaurants/Lynnwood
Food/Restaurants/Renton
```

The runtime agent learned to route local restaurants by city, using Lake Stevens, WA as home context when deciding local relevance. Cuisine belongs better as metadata/tag unless the vault explicitly has cuisine subfolders.

CLI hardening ideas:

- `snapshot --json` or a new `folders --json` command should expose canonical folder domains and preferred routing targets.
- `bookmark capture --auto-route` should route restaurants to `Food/Restaurants/{City}` when the city is known.
- If the city folder does not exist, either create it deliberately with a structured reason or place under `Food/Restaurants` with a `needsFolderReview` warning.
- Keep routing doctrine generated from live vault taxonomy where possible.

### 6. AI summaries belong in AI-owned fields, not user notes

The agent must not write generated text into user-owned bookmark notes unless explicitly asked. If enrichment is useful, use AI-owned metadata fields.

Current safe mutation pattern:

```bash
cider-cli bookmark update <id> --ai-summary "..." --enrichment-status complete
```

CLI hardening ideas:

- Make AI-owned fields explicit in command names and JSON output.
- Reject or warn when an automated agent attempts to write `notes` unless it passes an explicit `--user-authored` or equivalent flag.
- Track `aiSummarySource`, `aiSummaryModel`, `aiSummaryUpdatedAt`, and `enrichmentStatus`.
- Distinguish user notes from summaries in app UI and search ranking.

### 7. Batch capture needs per-link verification, not one final success

When a user drops many links, the agent should process them one by one and not fail the entire batch on one bad link.

Required per-link workflow:

1. duplicate check
2. add/create or select duplicate
3. metadata lookup/enrichment
4. title cleanup
5. route/move
6. verify with `bookmark get --json`
7. record per-link result

Final response should summarize:

- created count
- duplicate count
- error count
- final title + folder for each item
- any items left in `Inbox/Bookmarks` and why

CLI hardening ideas:

- Add `bookmark capture-batch --json` accepting newline-delimited URLs or JSON input.
- Continue on per-item failure and return an array of structured results.
- Include `errors[]`, `warnings[]`, and `needsUserReview` per item.

### 8. Final reports should be grounded in verified CLI state

The agent should not report the intended title or path. It should report what `bookmark get --json` returns after all mutations.

Minimum final report fields:

```json
{
  "id": "...",
  "title": "...",
  "url": "...",
  "folder": "...",
  "relativePath": "...",
  "created": "...",
  "updated": "..."
}
```

CLI hardening ideas:

- High-level capture commands should return this final verified object directly.
- Include `operationLog` for actions taken: duplicate check, add, enrichment, title update, move, verify.
- Include `userMessageSuggestion` for dumb/local agents to send concise, accurate feedback.

## Suggested High-Level CLI Contract

A future hardened command could look like:

```bash
cider-cli bookmark capture "https://www.tiktok.com/t/..." \
  --json \
  --auto-route \
  --enrich \
  --verify \
  --fallback-path "Inbox/Bookmarks"
```

Suggested JSON response:

```json
{
  "status": "created",
  "id": "UUID",
  "inputUrl": "https://www.tiktok.com/t/...",
  "canonicalUrl": "https://www.tiktok.com/@user/video/123",
  "duplicate": false,
  "title": {
    "initial": "Tiktok.Com",
    "provider": "Churro cheesecake does something to my soul...",
    "final": "Churro cheesecake recipe — Jose el Cook",
    "quality": "agent-cleaned"
  },
  "classification": {
    "kind": "reference",
    "contentType": "video",
    "domain": "Food",
    "path": "Food/Recipes",
    "confidence": "high",
    "reason": "TikTok oEmbed title and hashtags indicate a recipe."
  },
  "enrichment": {
    "status": "complete",
    "sources": ["tiktok-oembed"],
    "aiSummary": "Short recipe video for churro cheesecake."
  },
  "finalBookmark": {
    "id": "UUID",
    "title": "Churro cheesecake recipe — Jose el Cook",
    "folder": "Recipes",
    "relativePath": "Food/Recipes/Churro cheesecake recipe — Jose el Cook.webloc",
    "url": "https://www.tiktok.com/t/..."
  },
  "warnings": []
}
```

## Regression Scenarios To Add

- Saving a weak TikTok link with no useful metadata lands in `Inbox/Bookmarks`, not bare `Inbox`.
- A TikTok recipe short link gets a useful title and routes to `Food/Recipes`.
- A restaurant TikTok with city/address metadata routes to `Food/Restaurants/{City}`.
- A game TikTok routes to `Hobbies/Gaming`.
- A 3D-printing TikTok routes to `Hobbies/3D Printing`.
- An X/Twitter post about an AI/dev tool routes to `Tech/AI` or `Tech/Dev Tools` based on content.
- Duplicate detection catches exact short URLs and canonical provider URLs.
- The final response payload uses verified `bookmark get --json` state after move/retitle.
- Automated summary enrichment writes to AI-owned fields, never user notes by default.

## Source Session Notes

These notes were derived from a Telegram batch-capture session involving TikTok and X links. The important product lesson is not the specific links; it is that Cider should make the safe path the easy path for any model:

- stage opaque links safely
- enrich before deciding
- retitle when metadata becomes useful
- route only when confidence is adequate
- fallback to type-specific Inbox folders
- verify final state before telling the user it worked

## Observed Edge Case 7: Image/File Inbox Capture Has No High-Level CLI Add

### Session

User sent an image in Telegram and asked: “Can you add this image. Just put it in the inbox.”

### Observed Behavior

`cider-cli file` supports `list`, `get`, `move`, `delete`, `update`, `tag`, `untag`, and `enrich`, but there is no documented `file add` / `file import` command. To satisfy the request, the agent had to:

1. locate the Telegram/Hermes cached image file,
2. copy it directly into `Inbox/Images/`,
3. run `cider-cli file list --type image --json` so Cider’s file scan/indexing could discover it,
4. verify with `cider-cli file get <id> --json`.

This is workable for a careful agent, but it is not an ideal rail for a weaker/local model because it requires direct filesystem mutation and knowledge of the correct type-specific Inbox folder.

### Additional Quirk

Immediately after copy, `cider-cli file list --folder Inbox --json` returned an empty list, while `cider-cli file list --type image --json` showed the newly indexed file with:

```json
{
  "folder": "Inbox",
  "relativePath": "Inbox/Images/Cider library screenshot.jpg",
  "fileType": "image"
}
```

This makes `--folder Inbox` potentially misleading for files whose visible folder is reported as `Inbox` but whose folder association is nil/type-specific.

### Expected Behavior

Add a deterministic file capture/import command, e.g.:

```bash
cider-cli file add /path/to/image.jpg --path Inbox/Images --json --verify
```

or a higher-level capture command:

```bash
cider-cli capture /path/to/image.jpg --type image --fallback-path Inbox/Images --json --verify
```

The command should:

- choose the correct type-specific Inbox subfolder by default (`Inbox/Images` for images),
- avoid raw agents writing into `.cider` internals,
- copy/import the file safely,
- trigger/index file scanning if needed,
- return the final `id`, `displayTitle`, `fileType`, `relativePath`, and any warnings.

### Regression Scenario To Add

- Importing a local image through CLI lands in `Inbox/Images`, appears in `file list --type image --json`, and `file get <id> --json` reports the verified relative path.
- `file list --folder Inbox --json` either includes type-specific Inbox files or clearly documents/returns why it does not.

## Observed Edge Case 8: Pasted GIF Arrived As JPEG Still; Linked GIF Preserved Animation

### Session

User pasted/copied what they expected to be a GIF into Telegram and asked whether Cider would add and animate it. Hermes only received a cached JPEG still frame:

```text
~/.hermes/image_cache/img_67edcdfa62f5.jpg
JPEG image data, 410x480, 36,951 bytes
```

No `.gif`, `.webp`, or `.mp4` attachment appeared in the Hermes cache. The user then provided the Giphy media URL directly.

### Observed Behavior

Downloading the direct Giphy URL produced a real animated GIF:

```text
GIF image data, version 89a, 410 x 480
size: 9,214,133 bytes
frames: 192
animated: true
sha256: a3bb523a9878a470eecf2de706ed146e4351c05593cd86890f121451e45e70b9
```

The agent copied it to:

```text
Inbox/Images/Gritty Flyers mascot hockey GIF.gif
```

Cider discovered it through `file list --type image --json`, and `file get 48465A08 --json` verified:

```json
{
  "id": "48465A08-EBB7-4553-B03C-89C7B2538DD0",
  "displayTitle": "Gritty Flyers mascot hockey GIF",
  "filename": "Gritty Flyers mascot hockey GIF.gif",
  "fileSize": 9214133,
  "fileType": "image",
  "folder": "Inbox",
  "relativePath": "Inbox/Images/Gritty Flyers mascot hockey GIF.gif"
}
```

### Expected Behavior

A future file/capture command should preserve animated media when the input is a URL or attachment with animation, and report whether the stored asset is actually animated. For example:

```bash
cider-cli capture "https://media2.giphy.com/.../giphy.gif" \
  --type image \
  --fallback-path Inbox/Images \
  --json \
  --verify
```

Expected structured fields:

- `originalInputType`: `telegramAttachment` / `url`
- `detectedMimeType`: e.g. `image/gif` vs `image/jpeg`
- `isAnimated`: `true` / `false` / `unknown`
- `frameCount`: numeric when available
- `finalPath`
- `warning`: e.g. `Telegram delivered a JPEG still frame; provide the original GIF URL to preserve animation.`

### App Playback Follow-Up

User checked Cider after import and reported that the saved GIF did **not** appear to play/animate in the app, even though the underlying file is a valid animated GIF:

```text
/Users/minivish/CiderVault/Inbox/Images/Gritty Flyers mascot hockey GIF.gif
GIF image data, version 89a, 410 x 480
format=GIF size=(410, 480) frames=192 animated=True
```

This separates two issues:

1. capture/import correctness — the vault file is a real animated GIF; and
2. app preview/playback correctness — Cider may be rendering only a still frame or otherwise not animating GIF previews.

### Expected Behavior

A saved animated GIF should animate in the app wherever Cider presents image previews/detail views, or the UI should clearly indicate that animation playback is unsupported in that surface and offer an external/open-original action.

Potential implementation checks:

- confirm whether the app preview pipeline uses APIs/views that animate GIFs (`NSImageView`/SwiftUI `Image` may show only the first frame depending on loading path),
- preserve and pass the original `.gif` file URL/data to a GIF-capable renderer,
- avoid generating/using static thumbnails as the only detail preview for animated images,
- show an `Animated GIF` badge or metadata derived from frame count.

### Regression Scenario To Add

- Pasted Telegram GIF-like media that arrives as JPEG should be stored as a still image only if the user confirms, or should return a warning that animation was lost.
- Direct `.gif` URL capture should download the real GIF, preserve the `.gif` extension, verify `isAnimated == true`, and show up as an image file in `Inbox/Images`.
- Opening `Inbox/Images/Gritty Flyers mascot hockey GIF.gif` in Cider should animate, or the app should explicitly communicate that GIF playback is not supported and provide a way to open the original animated file.

## Observed Edge Case 9: Retitling In-Place Does Not Rename Generic Bookmark Files

### Session

User asked to triage generic items and the Inbox. Several bookmarks had enough metadata to produce clean titles and routes, but some already lived in a mostly-correct folder with generic filenames such as `Tiktok.Com.webloc`, `Tiktok.Com (2).webloc`, `Imdb.Com (2).webloc`, or `IMDb tt8633478.webloc`.

Examples verified during triage:

```text
Food/Restaurants/Edmonds/Tiktok.Com.webloc
  title: Kazoku sushi restaurant in Edmonds — Seattle Food Diva

Hobbies/Gaming/Tiktok.Com (2).webloc
  title: DND mapmaking and Canvas of Kings inspiration — DnD Vampire

Hobbies/Gaming/Tiktok.Com.webloc
  title: DND mapmaking tip - lumorafantasy

Inbox/Bookmarks/IMDb tt8633478.webloc
  title: Run (2020) — IMDb
```

### Observed Behavior

`cider-cli bookmark update <id> --title ...` successfully changed the bookmark title. But if the bookmark stayed in the same folder, the underlying `.webloc` filename / `relativePath` often remained generic. Running `bookmark move <id> --path <same-folder>` did not reliably force a rename either.

When an item moved from Inbox to a different folder, the resulting filename generally used the clean title. When the folder did not materially change, title and filename could diverge.

### Expected Behavior

For agent-driven cleanup, the CLI needs a deterministic way to keep title and path aligned without unsafe filesystem edits. Possible affordances:

```bash
cider-cli bookmark update <id> --title "Clean Title" --rename-file --json --verify
```

or:

```bash
cider-cli bookmark rename-file <id> --from-title --json --verify
```

Expected behavior:

- sanitize the current title into a valid `.webloc` filename,
- avoid collisions with ` (2)` suffixes as needed,
- update the bookmark file path through Cider’s normal mutation/index flow,
- return old/new `relativePath`, `title`, and whether the rename was applied.

### Regression Scenario To Add

- A bookmark in `Food/Restaurants/Edmonds/Tiktok.Com.webloc` updated to title `Kazoku sushi restaurant in Edmonds — Seattle Food Diva` should be renameable in-place to `Food/Restaurants/Edmonds/Kazoku sushi restaurant in Edmonds — Seattle Food Diva.webloc` through the CLI, without moving through a temporary folder or editing the filesystem directly.
