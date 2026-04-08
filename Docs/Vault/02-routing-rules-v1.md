# Routing Rules v1

> How incoming captures get placed into the vault. Fast, obvious routing first — refinement later.

## Core Principle

The agent should classify quickly and conservatively. When confident, route directly. When uncertain, put it in Inbox and move on. Do not spend 12 steps classifying a single URL.

## Decision Flow

```
1. Is it a URL?
   → Is it a restaurant/food place?     → Food/Restaurants/{Cuisine}/
   → Is it a recipe?                     → Food/Recipes/
   → Is it a product/shopping link?      → Life/Shopping/
   → Is it a game/gaming related?        → Hobbies/Gaming/
   → Is it a tech tool/tutorial?         → Tech/{Topic}/
   → Is it a travel destination?         → Life/Travel/
   → Is it a wallpaper/design asset?     → Hobbies/Wallpapers/ or Hobbies/Design Inspiration/
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
2. Route to: `Food/Restaurants/{Cuisine}/{Restaurant Name}.webloc`
3. If cuisine is unclear, use `Food/Restaurants/` directly
4. Cuisine subfolders: `Chinese`, `Japanese`, `Korean`, `Thai`, `Vietnamese`, `Indian`, `Mexican`, `Italian`, `American`, `Burgers`, `Coffee`, `Desserts`, `Seafood` — create others as needed

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
| Medium (likely but not certain) | Route to best guess, mention it in response |
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
→ `Food/Restaurants/Chinese/{Name}.webloc`
→ Sidecar with notes, city, cuisine, source

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
