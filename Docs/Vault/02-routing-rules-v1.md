# Routing Rules v1

> How incoming captures get placed into the vault. Fast, obvious routing first — refinement later.

## Core Principles

1. **Fast, obvious routing.** The agent should classify quickly and conservatively. When confident, route directly. When uncertain, put it in Inbox and move on. Do not spend 12 steps classifying a single URL.
2. **Inbox must be drained.** Inbox items must be triaged within the same session when possible. The agent should revisit Inbox items when new context is available. Inbox is not a long-term storage location.
3. **One location per item.** Each item must be routed to exactly one location. Do not place the same item in multiple folders.
4. **Merge before create.** Before creating a new entity, check if a matching one already exists. If it does, merge into it. Do not create duplicate folders or files for the same person, place, project, or topic. See Entity Resolution Rules for the lookup process.

## Decision Flow

```
1. Is it a URL?
   → Is it a restaurant/food place?     → Food/Restaurants/{City}/
   → Is it a recipe?                     → Food/Recipes/
   → Is it a product/shopping link?      → Life/Shopping/
   → Is it a game/gaming related?        → Hobbies/Gaming/
   → Is it a tech tool/tutorial?         → Tech/{Topic}/
   → Is it a travel destination?         → Life/Travel/ or Trip ideas/
   → Is it a movie/TV/watchlist item?     → Media/Movies/ or Media/TV Shows/
   → Is it a wallpaper/design asset?     → Wallpapers/ or Personal/Wallpapers/
   → Can't tell?                         → Inbox/Bookmarks/

2. Is it a note/text?
   → About a person?                     → People/{Name}/
   → About an active project?            → Projects/{Project}/
   → A how-to or troubleshooting?        → Tech/{Topic}/
   → A recipe or food note?              → Food/Recipes/
   → Can't tell?                         → Inbox/Notes/

3. Is it a file/image/media?
   → Screenshot for reference?           → Media/Screenshots/
   → Photo of a person?                  → People/{Name}/ or Media/Photos/
   → Photo of food/restaurant?           → Food/Restaurants/{Place}/
   → PDF manual or document?             → Route by content topic
   → Can't tell?                         → Media/ or Inbox/Files/

4. Is it a personal fact about someone?
   → Always → People/{Name}/
```

## URL Classification Signals

The agent uses these to decide quickly:

| Signal | Likely Domain |
|--------|--------------|
| TikTok/Instagram + food hashtags | `Food/Restaurants/` |
| TikTok/Instagram + product review | `Life/Shopping/` |
| YouTube + tutorial/how-to | `Tech/` |
| YouTube + gaming | `Hobbies/Gaming/` |
| Yelp, Google Maps, restaurant site | `Food/Restaurants/` |
| GitHub, Stack Overflow, dev docs | `Tech/` or `Projects/` |
| Amazon, product listing | `Life/Shopping/` |
| Reddit + hobby topic | Route by subreddit topic |
| News article | `Inbox/Bookmarks/` (too ambiguous) |

## Restaurant Routing (High Volume)

Restaurants are common enough to deserve specific rules:

1. Extract: name, cuisine type, city/neighborhood
2. Route to: `Food/Restaurants/{City}/{Restaurant Name}.webloc` when the city is known
3. If city is unclear, use `Food/Restaurants/` directly or `Inbox/Bookmarks/` if the item still needs triage
4. Cuisine belongs in metadata/tags unless the live vault taxonomy explicitly contains cuisine folders. Do not create cuisine folders just because a restaurant has a cuisine.

## Media / Watchlist Routing

IMDb, Letterboxd, trailer posts, and explicit movie/TV recommendations should route to media folders when the item type is clear:

1. Movies → `Media/Movies/{Title}.webloc`
2. TV series / shows → `Media/TV Shows/{Title}.webloc`
3. Ambiguous entertainment links where movie vs TV is unclear → `Inbox/Bookmarks/` until clarified
4. Do not mix image/media-file storage with watchlist bookmarks: `Inbox/Images` and other file Inbox folders are for captured files; `Media/Movies` and `Media/TV Shows` are for watchlist/reference bookmarks.

## Person Routing

1. If the person already has a folder in `People/`, add to it
2. If this is the first mention, create `People/{First Name}/profile.md`
3. If it's just a contact detail (no accumulated knowledge), a single `.vcf` file is fine
4. Promote to folder-per-person when they accumulate 3+ pieces of information

## Project Routing

1. If the project folder exists, add to it
2. If this is a new project, create `Projects/{Project Name}/README.md`
3. Don't create project folders for one-off tasks — those are todos

## Confidence Rules

| Confidence | Action |
|------------|--------|
| High (obvious domain match) | Route directly, no confirmation needed |
| Medium (likely but not certain) | Route to best guess, mention it in response. If entity resolution is also weak, prefer Inbox over incorrect routing. |
| Low (genuinely ambiguous) | Put in Inbox, tell the user |

## What NOT To Do

- Do not create new top-level folders
- Do not invent deep folder hierarchies for a single item
- Do not classify a URL as 5 different things — pick one
- Do not ask the user to classify every item (only ask when genuinely stuck)
- Do not move items between domains without the user's knowledge
- Do not duplicate an item across multiple folders — one canonical location

## Examples

### "Here's a great Chinese restaurant in Bellevue"
→ oEmbed/fetch metadata
→ `Food/Restaurants/Bellevue/{Name}.webloc`
→ Metadata/tags with cuisine, city, source

### "Ashley's shoe size is 8.5"
→ Check `People/Ashley/profile.md`
→ Append under a "Sizes" section
→ If no profile exists, create it

### "I fixed the Streamio buffering issue by changing DNS"
→ `Tech/Streaming/Streamio/troubleshooting.md`
→ Append with date and fix description

### "Check out this WoW addon"
→ Is user building it? → `Projects/WoW Addons/`
→ Just saving for reference? → `Hobbies/Gaming/WoW/`

### "Save this wallpaper"
→ `Hobbies/Wallpapers/{descriptive-name}.jpg`

### "Remind me about my dentist on April 15"
→ Create `.ics` event → `Inbox/Date Cards/`
→ Also note in `Life/Medical/` if it's a recurring provider

### Random article with no clear domain
→ `Inbox/Bookmarks/`
→ Agent says: "Saved to Inbox — let me know if you want it filed somewhere specific."
