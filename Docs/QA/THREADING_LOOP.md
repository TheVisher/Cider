# Threading Safety Loop

Automated audit for threading and concurrency safety across the Cider codebase.

## When to run
- After adding new async/await code
- After modifying ViewModels or Services
- Before releases
- When investigating crashes or race conditions

## How to run

Tell Claude: **"Run the threading safety loop"** — it will read this doc and know what to do.

## Setup

1. Create a branch: `git checkout -b threading-fixes`
2. Start the loop: `/loop 15m Run the threading safety loop per Docs/QA/THREADING_LOOP.md`
3. Let it run — cycles through each area, fixes violations, verifies with `swift build`
4. Review the diff when done, merge if clean

## Rules checked

1. **@MainActor on UI-touching code** — any code that updates `@Published` properties observed by SwiftUI must be `@MainActor`
2. **No bare DispatchQueue.main.async without guard** — prefer `@MainActor` or `MainActor.run`; if using DispatchQueue, guard against stale state (e.g., check `panel.isVisible` before updating UI)
3. **No force unwraps in async callbacks** — objects may be deallocated; use `[weak self]` and guard
4. **OSAllocatedUnfairLock for shared mutable state** — not `DispatchQueue` or `NSLock` for simple flag protection
5. **No synchronous file I/O on main thread** — `Data(contentsOf:)`, `FileManager` operations should be on background
6. **Task cancellation handling** — long-running Tasks should check `Task.isCancelled`
7. **No data races in KVO/NotificationCenter callbacks** — async callbacks may fire after object is invalid; guard with `[weak self]` and state checks
8. **Sendable compliance** — types shared across concurrency boundaries should conform to `Sendable` or use `@unchecked Sendable` with documented justification

## 3-pass verification

Each area requires 3 independent clean scans before PASS. If any scan finds a new violation, fix it and reset to 1/3.

## Areas (scan order)
App/ → Services/ → ViewModels/ → Views/Shared/ → Views/Bookmarks/ → Views/Notes/ → Views/Home/ → Views/Search/ → Views/Settings/

Note: Models/ and Utilities/ are excluded — they are pure data types and static tokens with no concurrency concerns.

## Progress tracking

Results are logged in `Docs/QA/THREADING_AUDIT.md` with a progress tracker table and detailed fix log. Create this file on first run.

## Known non-violations (skip these)
- `DispatchQueue.main.async` in AppKit lifecycle code (applicationDidFinishLaunching, etc.) — AppKit convention
- `@unchecked Sendable` with a comment explaining why — intentional
- Synchronous reads of small config files at startup — acceptable tradeoff
- `nonisolated(unsafe)` on logger instances — Swift concurrency convention
