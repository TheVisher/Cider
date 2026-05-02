# Floatable Surfaces Product Decisions

Date recorded: 2026-04-30

This captures the decisions and follow-ups from the NSPanelChange work so the useful product reasoning survives outside the chat.

## Direction

Cider should be a normal macOS app with a regular main window. The whole app should no longer be treated as one giant `NSPanel`.

`NSPanel` should be used for individual floatable surfaces: notes, bookmark metadata, contact cards, todos, quick intake, and other small work surfaces that benefit from staying near the user's current context.

The main app remains the authoritative place for library browsing, navigation, search, folders, tabs, and full editing workflows. Floating panels are companion surfaces, not a second full app shell.

## Smart Recall

The Option-key shortcut should evolve into smart recall.

- Default behavior can remain double-tap Option.
- The existing setting for single-tap Option versus double-tap Option should stay.
- Single-tap Option should only trigger on a quick tap, not when the user holds Option as a modifier.
- Smart recall should prefer the last useful floating surface, such as a note or bookmark panel.
- If there is no recallable floating surface, the shortcut should fall back to opening the main app.
- Utility panels such as the Drop Zone should not become the primary recall target.

Position behavior:

- If "open near mouse" is enabled, recalled panels should follow the cursor and respect the active display.
- If "remember position" is enabled, recalled panels should restore their last position.
- Saved positions should translate sensibly when the cursor is on a different monitor.

## Reanchoring

Floating item panels should have an explicit reanchor action.

Reanchor means: open the main app to the same item, then close or dock the floating copy so the user is back in the full context.

This matters because one control should not have to mean both "bring this panel back" and "take me to the full app." Floating surfaces need a clear way home.

## Bookmark Floating Panels

Bookmark floating panels should feel consistent with the in-app metadata slide-out.

Preferred layout:

- Large preview/media area on the left.
- Metadata rail on the right.
- Metadata rail can collapse when space is tight or the user wants a focused preview.
- URL should be actionable.
- Metadata should include useful fields, not only notes.
- Image previews should preserve aspect ratio and stay inside their panel area when resized.

The floating panel can be information-rich, but it should not become a full duplicate of the library. It should show enough context to use the item, with reanchor available for deeper organization.

## Notes Floating Panels

Floating note panels should use the same editing chrome as notes in the main app.

They should not fall back to raw Markdown without the expected editing toolbar. A popped-out note should still feel like a note editor.

## Drop Zone

The Drop Zone is a quick intake surface.

Current direction:

- Dragging to the Cider menu bar icon can reveal the Drop Zone.
- Clicking the menu bar icon opens the normal menu.
- The menu can include "Show Drop Zone."
- The Drop Zone can be pinned open for batch intake.
- When unpinned, it should auto-dismiss with a visible smooth progress bar.
- Hovering should pause auto-dismiss.
- Leaving hover should resume auto-dismiss.
- Dropping an item should not leave the Drop Zone stuck in drag-over state.
- Recent items should persist across auto-dismiss and show the last few successful drops.
- Dropped image files should use the source filename as the bookmark title.
- URLs should resolve useful titles when metadata is available.

Visual/product notes:

- Keep the header compact.
- Avoid redundant explanatory text under the title.
- Rounded corners should match the Cider floating surface style.
- Recents should scroll instead of pushing the progress bar off the panel.

Future direction:

- The Drop Zone may grow into a small menu-bar or notch-like utility surface.
- It could show todos, events for the day, contacts, bookmark search, and recent saves.
- This should remain optional and easy to disable.

## Universal Floatability

Future feature work should assume detail surfaces may run in two contexts:

1. Embedded in the main app.
2. Floating in an `NSPanel`.

That means new detail surfaces should avoid assuming one fixed container, one fixed title bar, or one fixed activation model. Shared content views should be reusable, with window-specific chrome handled separately.

## Follow-Ups

- Masonry resizing now works, but image-heavy masonry can still feel laggy during resize.
- Continue polishing traffic lights, top bars, rounded edges, focus behavior, and drag zones on floating panels.
- Keep testing tab reordering versus window dragging, especially immediate click-drag behavior.
- Decide later whether remote feature branches such as `origin/codex/NSPanelChange` should be pruned after merge.
- The separated website and brand work was preserved locally on `codex/cider-site-refresh`.

