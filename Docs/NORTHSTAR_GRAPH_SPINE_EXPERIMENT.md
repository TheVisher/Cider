# North Star Graph-Native Second-Brain Prototype

This document is the full context for the `northstar-graph-spine-prototype` experiment branch.

## Branch and tracking

- Worktree: `/Users/minivish/Cider-worktrees/northstar-graph-spine-prototype`
- Branch: `northstar-graph-spine-prototype`
- Parent milestone: `CID-480 / 361d49` — Universal source-backed object linking
- Tracking card: `CID-487 / 2c5423` — Experimental branch: graph-native second-brain spine prototype

This is intentionally an ambitious isolated branch. Broad changes are allowed here because `main` is protected by isolation. The goal is not a clean tiny patch; it is to see how far Cider can move toward a graph-native second-brain spine in one coherent prototype.

## Required reading

Read these before coding:

- `Docs/NORTH_STAR.md`
- `Docs/STORAGE.md`
- `Docs/ARCHITECTURE.md`
- `Docs/PRODUCT.md`
- `Docs/FEATURES.md`
- `Docs/AGENT.md`
- `Docs/CLI.md`
- this file
- Kanban milestone/card context for CID-480 and children CID-481 through CID-487

Helpful commands:

```bash
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board milestone inspect 2afee0 --milestone 361d49 --json
/Users/minivish/Cider/.build/arm64-apple-macosx/debug/cider-cli board children 2afee0 --card 361d49 --json
```

## Vision

Cider should become the user-owned local second-brain memory substrate. Hermes, Codex, ChatGPT, local MLX, or any future LLM should be replaceable reasoning layers over the same Cider vault. The vault should be understandable to both a human browsing the app and an LLM using CLI/API/context tools.

The user wants to naturally talk to Cider, especially while driving, and have that normal narration become connected, source-backed memory: morning/evening drive journals, dinner notes, what the kids liked/disliked, what Jami liked/disliked, gifts, drinks, flowers, restaurants, foods, movies, trips, reminders, todos, saved URLs/bookmarks/files/media, and anything else that represents real life.

Cider should preserve the raw source entry, extract useful facts/mentions, link them to relevant objects, and show those links everywhere they matter.

## Core principle

Every saved source can produce reviewable object and relation candidates:

- journal entry
- chat message
- voice transcript
- URL/bookmark
- note
- file
- media item
- reminder/todo/event
- contact/project/place/space item

Sources are raw evidence. Accepted Cider graph facts should be source-backed and reviewable. URLs are often evidence for a higher-level object; they are not always the object itself.

## Desired pipeline

```text
Raw source item
  -> Mention extraction
  -> Object candidate / relation candidate
  -> Resolution against existing Cider objects
  -> If unresolved or low confidence: Review Queue / Needs Triage
  -> User accepts / rejects / corrects / manually completes / delegates enrichment
  -> Accepted object/fact/relation with source backlink
  -> Object surfaces show connected context
  -> Recall uses graph facts first, source search second
```

## Examples

### Journal to contact preference

User journals: “I gave Jami that pineapple coconut drink and she loved it.”

Cider should preserve the source journal entry and create a reviewable candidate:

- source: Daily Journal entry
- subject: Jami contact
- relation/fact: likes drink
- object/value: pineapple coconut drink
- source quote
- confidence
- review state

After acceptance, Jami’s contact/context surface should show the drink preference with source backlink. Later recall should answer “What drink did Jami really like?” from accepted contact graph/context, not hidden LLM memory.

### Journal to missing media object candidate

User journals: “I watched The Way Way Back last night.”

If no matching media item/bookmark exists, Cider should not silently invent permanent truth. It should create a Review Queue candidate:

- title: The Way Way Back
- typeGuess: movie
- action/status: watched
- watchedDate: inferred from “last night”
- source journal entry and quote
- possible external matches such as IMDb/TMDb
- safe actions: create lightweight media item, search IMDb/TMDb/Letterboxd, link existing item, mark wrong extraction, ignore/reject, delegate enrichment

If a saved IMDb URL or existing media item exists, create a reviewable typed relation: `Journal Entry --watched--> Media Item`.

### URL capture to represented object

When saving an IMDb URL, restaurant URL, recipe URL, product URL, YouTube URL, GitHub URL, etc., Cider should treat the URL as a source/bookmark and optionally link it to a higher-level object:

- `Bookmark imdb.com/title/... --represents/source_for--> Media Item`
- `Restaurant website bookmark --represents/source_for--> Place/Restaurant`

If no object exists, create a reviewable object candidate with safe actions.

### Ambiguous mention to review queue

User journals: “We went to Cactus and Jami liked the margarita.”

Cider might not know if Cactus is a restaurant/place, plant/object, existing note/topic, or something else. It should create a Review Queue / Needs Triage item asking what Cactus is, with choices and a delegate-enrichment option. If the user chooses restaurant/place, link the journal visit, Jami’s liked drink, the restaurant object, and the source entry.

## What to build in this branch

Try to implement a coherent vertical slice of the graph-native spine. Prefer a working prototype over a tiny isolated patch.

Include as many as feasible:

1. Universal object/relation candidate model: raw source owner/ref, source quote/snippet, mention text, type guesses, relation/action guesses, confidence/evidence, review state, safe actions, accepted target.
2. Review Queue integration for unresolved candidates: low-confidence/unresolved objects visible in review/triage, inspectable via JSON, with accept/reject/correct/delegate actions or stubs.
3. Journal extraction beyond contacts: media/movie mentions, places/restaurants, food/drink/preference facts tied to contacts where possible.
4. URL/bookmark object resolution: classify common domains/types and create `represents` / `source_for` candidate relations.
5. Object context/backlinks: accepted or previewed candidates retrievable through item context/owner context JSON; facts point to source evidence.
6. Delegated enrichment action prototype: safe action to ask LLM/web agent for matches; results remain reviewable evidence.

## Safety and trust rules

- Do not mutate the live user vault in tests; use temp/test vaults.
- Do not silently promote extracted AI facts into accepted graph truth.
- Reviewable candidates are safe; accepted facts require explicit accept path or documented policy.
- Always preserve source backlinks and source quotes/snippets.
- Keep data local-first and inspectable.
- Prefer CLI JSON surfaces and tests so Hermes/LLMs can use the results.

## Desired deliverables

At the end, update CID-487 and report:

1. Branch name and commit SHA(s).
2. What coherent vertical slice was implemented.
3. Files/data models/services/CLI commands changed.
4. How to build and launch the prototype app.
5. Exact tests run and results.
6. What remains prototype-only or incomplete.
7. How to split the experiment into mergeable cards if successful.
8. Screenshots or app verification steps if UI changed.

## Suggested verification

Create focused tests for scenarios like:

- journal mention creates unresolved media candidate for “The Way Way Back”
- journal mention creates contact preference candidate for “Jami liked pineapple coconut drink”
- ambiguous “Cactus” mention lands in review/triage with possible types
- IMDb URL capture creates/proposes `represents/source_for` media candidate
- accepting a candidate creates typed relation with source backlink
- rejecting a candidate does not create graph truth
- item/contact/media context can show source-backed linked facts

Run focused tests first, broader affected slices if feasible. Do not claim full suite unless it actually completes.

## Tone

Be bold in architecture, but make it inspectable and testable. If current architecture fights the design, document where and propose a cleaner spine.
