# Cider Agent Save Routing Design

**Date:** 2026-04-17
**Status:** Approved design, pending implementation plan

## Summary

Improve the in-app agent's save behavior for bookmarks, notes, and contacts by teaching it the existing vault routing doctrine that previously worked well in the Claude Code flow.

This is intentionally a prompt-and-instructions experiment, not a new routing subsystem. The goal is to see whether the in-app agent can route obvious captures into the right folders by following stronger vault rules before any helper tool or classifier is added.

## Problem

Today, agent-created bookmarks and notes often land in Inbox because the current in-app assistant instructions are too generic. The storage and tool layers already support saving into folders when a folder is specified, but the model is not being taught the vault taxonomy or told to route before creating.

This creates a gap between the old Claude Code vault behavior and the in-app agent behavior:

- The old Claude flow had explicit routing doctrine and examples for domains like `Food`, `People`, `Tech`, and `Life`.
- The in-app agent currently gets broad tool-usage rules, but not the vault behavior contract.
- As a result, obvious captures like recipe videos or person/contact facts are not consistently filed where they belong.

## Goals

- Improve routing for new agent-created bookmarks, notes, and contacts.
- Reuse the existing vault taxonomy and routing doctrine already documented in the repo.
- Prefer direct filing when the destination is obvious.
- Fall back to Inbox when uncertain, with an explicit explanation in the assistant's response.
- Keep the first pass easy to test and easy to back out.

## Non-Goals

- No new routing service.
- No new folder suggestion tool.
- No hard-coded classifier or confidence score system in app code.
- No routing changes for todos or date cards in this pass.
- No background reclassification or Inbox draining automation in this pass.

## Proposed Approach

### Approach A: Prompt-only routing doctrine

Expand the system instructions for the in-app assistant so they include the same vault behavior contract Claude Code used:

- classify the incoming capture
- resolve likely existing entities or destinations
- route to a folder before creating when possible
- use Inbox when the destination is genuinely unclear

This is the recommended approach for v1.

**Why this approach:**

- It matches what already worked in practice with Claude Code.
- It keeps implementation risk low.
- It tests the real product question first: whether stronger instructions are enough.
- It preserves a clean path to add a helper tool later only if needed.

### Approach B: Prompt plus helper tool

Add a folder-routing helper such as `suggestFolder` or `listFolderCandidates` alongside stronger routing instructions.

**Tradeoff:** More reliable than prompt-only, but adds code and API surface before proving the prompt gap is the real issue.

### Approach C: App-side routing logic

Build deterministic code that classifies items into domains and subfolders before the create tools save them.

**Tradeoff:** Most controlled, but too heavy and too early for this problem.

## Routing Rules For This Pass

The in-app assistant should adopt the existing vault routing rules already documented in:

- [docs/Vault/CLAUDE-vault.md](/Users/minivish/Cider/docs/Vault/CLAUDE-vault.md)
- [docs/Vault/02-routing-rules-v1.md](/Users/minivish/Cider/docs/Vault/02-routing-rules-v1.md)

For this experiment, the important behavioral rules are:

- Do not invent new top-level folders.
- Use the locked top-level domains already defined by the vault doctrine.
- For bookmarks and notes, choose a folder before creating when the destination is reasonably clear.
- For contacts and person facts, prefer `People/{Name}` style routing.
- When routing is unclear, save to Inbox instead of guessing wildly.
- Tell the user where the item was saved and why.

## Item-Type Scope

### Bookmarks

The assistant should classify obvious captures before saving:

- recipe or food content -> `Food/Recipes/` or another obvious Food subfolder
- restaurant or place -> `Food/Restaurants/...`
- person-specific reference -> `People/{Name}/`
- tech/tutorial content -> `Tech/...`
- practical life logistics -> `Life/...`
- unclear reference -> Inbox

The key change is not adding new bookmark storage behavior. It is teaching the model to provide `folderName` more consistently when calling the existing bookmark save tools.

### Notes

The assistant should apply the same domain routing logic to new notes:

- person facts or profile notes -> `People/{Name}/`
- project notes -> `Projects/...`
- troubleshooting or how-to notes -> `Tech/...`
- food or recipe notes -> `Food/...`
- unclear notes -> Inbox

Again, the storage layer already supports folder assignment. The experiment is about improving the model's decision before save.

### Contacts

Contacts are simpler in this pass:

- new contacts should default to the appropriate `People/{Name}` flow
- if the agent is capturing a person and associated details, it should prefer routing related notes/files to the same person area when the request is clearly person-centric

This does not require broad new contact architecture. It mainly requires clearer instructions that person-related captures belong under `People`.

## Product Behavior

### High-confidence behavior

When the destination is obvious from the request or source material, the assistant should save directly into the matching folder and say so.

Example:

- "Saved this recipe bookmark to `Food/Recipes`."

### Low-confidence behavior

When the destination is unclear, the assistant should save to Inbox and explain the uncertainty in plain language.

Example:

- "Saved this to Inbox because it looked food-related, but I wasn't confident whether it belonged in `Food/Recipes` or a restaurant folder."

This keeps capture unblocked while making the routing decision visible.

## Implementation Shape

This pass should stay small and localized.

### Prompt changes

Update the assistant system instructions so they:

- describe the vault routing contract
- describe the locked top-level domains
- instruct the model to route before create for bookmarks, notes, and contacts
- explicitly prefer Inbox over incorrect routing when uncertain
- require the assistant to mention the destination in its user-facing confirmation

These changes should be applied in both assistant backends that construct system prompts, so routing behavior is consistent across providers.

### Tool contract expectations

The create tools do not need new parameters if they already accept optional folder input. Instead, the revised prompt should make better use of the existing tool surface.

If a user asks the agent to save something and the destination is clear, the model should call the relevant create tool with a folder.

If the destination is not clear, the model should create without a folder and explain the Inbox fallback.

## Observability

This pass should rely on existing observability instead of introducing new routing telemetry.

Useful signals already available:

- mutation audit rows for creates and folder assignments
- filesystem placement of the saved artifact
- the assistant's visible confirmation message

The outcome we care about is simple: obvious saves should stop landing in Inbox unnecessarily.

## Risks

### Prompt inconsistency

The model may still ignore or partially follow the routing doctrine in some cases. That is acceptable for this experiment because the point is to measure whether prompt guidance alone gets close enough.

### Over-eager routing

Stronger routing instructions could make the agent overconfident. The prompt must explicitly prefer Inbox when uncertain.

### Provider divergence

Different backends may respond differently to the same routing instructions. The updated doctrine should be mirrored across providers to reduce drift.

## Testing

This pass should be evaluated with real behavior checks rather than only unit tests.

Recommended manual test cases:

1. Save a recipe TikTok bookmark.
Expected: routed into `Food/Recipes` or another clearly appropriate Food folder, not Inbox.

2. Save a person contact.
Expected: routed through the `People` domain behavior, not left as a generic Inbox capture.

3. Save an ambiguous article.
Expected: saved to Inbox with a brief explanation of uncertainty.

4. Save a tech troubleshooting note.
Expected: routed into `Tech/...` rather than Inbox.

Success criteria for v1:

- obvious bookmark and note saves route correctly more often than not
- ambiguous captures still fail safely to Inbox
- the assistant tells the user where it saved the item

## Rollout

This should ship as a small behavior change with no schema or migration work.

Recommended order:

1. Update prompt instructions for all in-app assistant providers.
2. Manually test bookmark, note, and contact saves against real examples.
3. Observe whether obvious saves stop falling into Inbox.
4. Only if prompt-only behavior is still not good enough, consider a small helper tool in a follow-up design.
