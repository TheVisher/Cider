# Dead Code Detection Loop

Automated audit for finding unused functions, variables, types, and imports across the Cider codebase.

## When to run
- After major refactors
- Before releases (reduce binary size)
- Quarterly cleanup
- When the codebase feels bloated

## How to run

Tell Claude: **"Run the dead code detection loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b dead-code-cleanup`
2. Start the loop: `/loop 15m Run the dead code detection loop per Docs/QA/DEAD_CODE_LOOP.md`
3. Let it run — cycles through each area, removes dead code, verifies with `swift build`
4. Review the diff when done, merge if clean

## What to check

1. **Unused private functions** — `private func` or `private static func` that nothing calls within the file
2. **Unused private variables** — `private var` or `private let` that nothing reads
3. **Unused parameters** — function parameters that are never referenced in the body (use `_` prefix)
4. **Unused imports** — `import` statements for frameworks not used in the file
5. **Commented-out code blocks** — large blocks of `//` commented code that should be deleted (git has history)
6. **Empty extension blocks** — `extension Foo { }` with no members
7. **Unused type definitions** — `struct`, `enum`, `class` that nothing references outside their file (if private) or across the codebase (if internal)
8. **Unused protocol conformances** — protocols declared but never used as a type constraint

## How to verify

For each candidate:
1. Search the ENTIRE codebase for references (not just the current file)
2. Check if it's used via protocol conformance, KVO, or Objective-C selectors (@objc)
3. Check if it's referenced in JS bridge code (TipTap message handlers)
4. Only remove if truly unreferenced

After removal: `swift build` must pass. If build fails, the code wasn't actually dead — revert immediately.

## 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds new dead code, remove it and reset to 1/3.

## Areas (scan order)
App/ → Models/ → Utilities/ → Services/ → Services/AI/ → ViewModels/ → Views/Bookmarks/ → Views/Notes/ → Views/Home/ → Views/Shared/ → Views/Search/ → Views/Settings/ → Views/AIAssistant/

## Progress tracking

Results are logged in `Docs/QA/DEAD_CODE_AUDIT.md` with a progress tracker table and detailed fix log. Create this file on first run.

## Known non-violations (skip these)
- `@objc` functions — may be called via selectors from AppKit/NotificationCenter
- Functions referenced in `#selector()` — runtime dispatch
- Protocol requirement stubs — required even if body is empty
- `CodingKeys` enums — used by Codable even if not explicitly referenced
- Public/internal API that may be used by future code — only remove `private` dead code with certainty
- JS message handler names in ViewModels — called from TipTap WebView
- `@IBAction` / `@IBOutlet` — Interface Builder references
