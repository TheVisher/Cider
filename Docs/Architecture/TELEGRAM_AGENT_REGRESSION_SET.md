# Telegram Agent Regression Set

## Purpose

Use this prompt set to validate the current Telegram-backed Codex runtime in one broad pass instead of re-testing each implementation card in isolation.

This set is intended to cover:

- save/capture behavior
- count routing
- recent-item routing
- duplicate and bookmark existence routing
- broad topical exploration
- item-specific retrieval
- durable-memory behavior
- logging/observability checks

## Rebuild

- `swift build -c debug`

## Test Pass

### 1. Save A URL

Prompt:

- Send a real URL with a short instruction like `save this`

Expected:

- the URL is captured as a bookmark
- the reply sounds natural and confirms the save without stiff tool narration

### 2. Count Questions

Prompts:

- `How many bookmarks do I have?`
- `How many events do I have?`
- `How many contacts, notes, and bookmarks do I have?`

Expected:

- counts are treated as app-backed totals
- no drift into raw filesystem counting
- no `vault unavailable` style answer

### 3. Recent Activity

Prompts:

- `What are my 5 most recent saves?`
- `What are my 5 most recent saves in the whole vault?`
- `What did I save most recently, not just today?`

Expected:

- whole-vault phrasing does not behave like a 24-hour-only query
- numeric requests preserve the requested limit
- replies do not claim older eligible items are unavailable when they should qualify

### 4. Duplicate / Existence

Prompts:

- `Do I already have this URL saved?` with a known saved URL
- `Have I saved this before?` with a URL that is not saved
- `Do I have a bookmark about <topic>?`

Expected:

- URL checks behave like duplicate checks
- bookmark existence questions behave like bookmark-aware lookups
- non-URL existence questions still verify current vault state

### 5. Broad Topic Exploration

Prompts:

- `What do I have about <topic>?`
- `Show me what I have on <topic>.`
- `What contacts, notes, or bookmarks do I have related to <topic>?`

Expected:

- replies feel grounded in a vault-wide lookup
- cross-entity questions do not collapse into a single type without evidence
- answers stay current-vault-backed rather than memory-only

### 6. Item-Specific Retrieval

Prompts:

- `Show me notes about <topic>.`
- `Find bookmarks about <topic>.`
- `What todos do I have about <topic>?`
- `Show events about <topic>.`

Expected:

- entity-specific questions feel scoped correctly
- no invented matches
- if nothing exists, the reply says so plainly

### 7. Ambiguous Retrieval

Prompts:

- `Find something I saved about <topic>.`
- `Where is the thing I saved about <topic>?`
- `I saved something about <topic> before, can you find it?`

Expected:

- ambiguous retrieval starts with a broad vault lookup
- if results are mixed, the answer stays grounded and can ask a short clarifying follow-up

### 8. Durable Memory

Prompts:

- share one casual low-value chat detail
- share one durable preference or repeated pattern
- ask later about that preference or pattern

Expected:

- durable preferences/patterns are treated as better memory candidates than casual chatter
- raw factual data is still framed as belonging in structured entities when appropriate

### 9. Logging / Observability

Check:

- open Console.app or another log viewer for Cider

While running the prompts above, verify:

- routing-choice logs appear for process-runtime turns
- failure logs are clearer if a bad turn happens
- heuristic warnings only appear when a reply strongly suggests index fallback or raw filesystem inspection
- healthy turns do not produce excessive noisy warnings

## Pass Criteria

- save, count, recent, duplicate, search, and memory behavior all feel coherent in one pass
- replies sound like a vault-aware assistant rather than a generic shell model
- no obvious filesystem-count drift on normal factual questions
- no obvious stale-memory-over-vault mistakes
- logs are useful without becoming spammy

## Follow-Up

After each meaningful runtime or instruction change:

1. re-run this regression set
2. record any failures or odd replies
3. convert repeated failures into new focused implementation cards
