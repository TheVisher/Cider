# Convention Enforcement Loop

Automated audit for enforcing CLAUDE.md coding conventions across the Cider codebase.

## When to run
- After major feature work
- Before releases
- When onboarding new patterns
- Any time you want to validate convention compliance

## How to run

Tell Claude: **"Run the convention enforcement loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b convention-fixes`
2. Start the loop: `/loop 15m Run the convention enforcement loop per Docs/QA/CONVENTION_LOOP.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

## Rules checked

1. **No `print()` statements** — use `os.Logger` instead (print is invisible when launched from Dock)
2. **No direct file deletion** — always use `TrashStorage` + `CiderUndoManager`
3. **Notification names** — must use `cider.` prefix, centralized in Constants.swift
4. **No `as?` for CF types** — use `unsafeDowncast` after `CFGetTypeID` check
5. **No raw app names in AppleScript** — use `application id` (bundle ID)
6. **Shell.run() safety** — must use Process with argument arrays, no shell interpretation
7. **No `.glassEffect()`** — use `NSVisualEffectView` with `.underWindowBackground`
8. **No `makeKeyAndOrderFront`** — use `orderFront` to avoid stealing focus
9. **CiderConfig pattern** — new properties must use `decodeIfPresent` + fallback in `init(from:)`
10. **No local `@State` copies of ViewModel data** — render directly from ViewModel to avoid sync bugs

## 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3. This ensures thoroughness.

## Areas (scan order)
App/ → Models/ → Utilities/ → Services/ → Services/AI/ → ViewModels/ → Views/Bookmarks/ → Views/Notes/ → Views/Home/ → Views/Shared/ → Views/Search/ → Views/Settings/ → Views/AIAssistant/

## Progress tracking

Results are logged in `Docs/QA/CONVENTION_AUDIT.md` with a progress tracker table and detailed fix log. Create this file on first run using the same format as `CODE_AUDIT.md`.

## Known non-violations (skip these)
- `print()` inside `#Preview` blocks
- `print()` in test targets
- `os.Logger` definition lines themselves
- TrashStorage definition/implementation files
- Notification name definitions in Constants.swift (source of truth)
