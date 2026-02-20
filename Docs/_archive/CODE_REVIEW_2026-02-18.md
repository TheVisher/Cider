# Cider Code Review Findings (2026-02-18)

This captures the latest full code review findings, ordered by severity.

## High

1. **Potential data loss in note restore path**  
   `TrashStorage.restoreNote` can continue cleanup after a failed file move from trash, which can orphan note files.
   - File refs: `Sources/Cider/Services/TrashStorage.swift:162`, `Sources/Cider/Services/TrashStorage.swift:180`

## Medium

1. **Carbon fallback hotkeys can consume keys even when disabled**  
   In fallback mode, disabled hotkeys can still report handled, causing `Opt+N`/`Opt+B` to be swallowed.
   - File refs: `Sources/Cider/Services/NotesHotkeyDetector.swift:166`, `Sources/Cider/Services/BookmarksHotkeyDetector.swift:190`

2. **Project storage does not follow bookmarks directory changes**  
   `ProjectStorage` remains bound to its initial path when bookmarks directory changes.
   - File refs: `Sources/Cider/Services/ProjectStorage.swift:10`, `Sources/Cider/App/AppDelegate.swift:120`

3. **Main-thread IO risk at startup/directory-switch**  
   Notes/bookmarks loading paths perform heavy scans/parsing on main actor.
   - File refs: `Sources/Cider/Services/NotesStorage.swift:40`, `Sources/Cider/Services/BookmarksStorage.swift:467`

4. **Global font scaling now repeatedly decodes config on render path**  
   `CiderFont` token access calls `CiderConfig.load()` frequently.
   - File refs: `Sources/Cider/Utilities/CiderFont.swift:11`, `Sources/Cider/Models/CiderConfig.swift:163`

5. **Undo-toast hover can make undo window effectively unbounded**  
   Hover behavior resets timer/progress instead of only pausing.
   - File ref: `Sources/Cider/App/AppDelegate.swift:586`

## Low

1. **Some UI elements still ignore text-size preference**  
   A few fixed-size icon paths remain unscaled.
   - File refs: `Sources/Cider/Utilities/CiderFont.swift:93`, `Sources/Cider/Views/Notes/NotesPanelView.swift:511`

## Open Questions / Assumptions

1. Undo window behavior: expected to be bounded with hover pause, not hover reset.
2. Disabled hotkeys: expected to pass through key events in both event-tap and Carbon fallback paths.

## Testing Gaps

1. No focused tests cover:
   - Trash restore failure handling
   - Disabled-hotkey pass-through under Carbon fallback
   - Storage rebinding after directory changes
2. Existing tests pass, but mostly cover notes codec/storage regression paths.
