# Documentation Health Loop

Automated audit for keeping docs accurate, consolidated, and in sync with the actual codebase.

## When to run
- After major feature work or refactors
- Quarterly maintenance
- When docs feel stale or contradictory
- Before onboarding someone new to the project

## How to run

Tell Claude: **"Run the docs health loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b docs-cleanup`
2. Start the loop: `/loop 15m Run the docs health loop per Docs/QA/DOCS_LOOP.md`
3. Let it run — cycles through each docs folder, validates against code, fixes/consolidates
4. Review the diff when done, merge if clean

## What to check

### 1. Accuracy — does the doc match the code?
- File paths mentioned in docs — do they still exist?
- Code patterns/examples — do they match current implementation?
- API/function names — have they been renamed or removed?
- Architecture descriptions — does the code still work this way?
- Feature descriptions — is the feature still implemented as described?

### 2. Staleness — is the doc still relevant?
- Does the doc describe something that was removed or replaced?
- Are there TODO/FIXME items that were already completed?
- Are there "planned" features that were already shipped or abandoned?
- Are dates/timelines outdated?

### 3. Duplication — is the same info in multiple places?
- Same pattern described in two docs — consolidate into one, reference from the other
- CLAUDE.md duplicating what's in a doc — remove from CLAUDE.md, keep the reference
- Overlapping docs that could be merged

### 4. Completeness — is anything missing?
- New features with no doc coverage
- Patterns used across the codebase but undocumented
- Known gotchas discovered during development but not written down

### 5. Organization — is it in the right folder?
- Doc content doesn't match its folder (e.g., architecture doc in Product/)
- Doc could be split into multiple focused docs
- Doc is too long and should be broken up

## How to fix

- **Stale info**: Update to match current code, or delete if no longer relevant
- **Duplicates**: Pick the better version, consolidate, add a reference from the other location
- **Wrong folder**: `git mv` to the correct folder
- **Missing docs**: Create a stub noting what should be documented (don't write full docs without user input on scope)
- **Dead references**: Fix paths, or remove references to deleted features

After changes: verify any code examples still compile conceptually (no need to `swift build` for pure doc changes).

## 3-pass verification

Each docs folder requires 3 independent clean scans before PASS. If any scan finds issues, fix them and reset to 1/3.

## Folders (scan order)
Architecture/ → Design/ → Conventions/ → Features/ → Product/ → QA/ → Shared/ → CLAUDE.md

## Progress tracking

Results are logged in `Docs/QA/DOCS_AUDIT.md` with a progress tracker table and detailed fix log. Create this file on first run.

## Known non-issues (skip these)
- `_archive/` folder — intentionally outdated, don't audit
- Vision docs describing future plans — these are aspirational, not meant to match current code
- CLAUDE.md being brief — that's by design, it references docs instead of duplicating them
