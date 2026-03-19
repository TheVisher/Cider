# Notes Editor Smoke Checklist

Run this checklist before shipping any notes/editor changes.

## Core Editing
- Create a new note and verify autosave status transitions to `Saved`.
- Type plain text, close note, reopen, and confirm content persisted exactly.
- Verify double line breaks persist after reopen.
- Verify `Undo` and `Redo` both work from toolbar and menu.

## Slash Menu
- Type `/` and confirm popup appears near caret.
- Navigate with `ArrowUp`/`ArrowDown` and confirm highlighted item changes.
- Press `Enter` and confirm selected slash command is inserted.
- Click a slash command item and confirm the clicked item (not adjacent) is inserted.

## Formatting
- Apply `Bold`, `Italic`, `Underline`, and link add/remove.
- Create heading with `#` and verify left/center/right alignment applies.
- Close/reopen and confirm heading alignment persists.

## Lists and Tasks
- Create bullet, numbered, and task lists from slash menu.
- Toggle task item checkboxes and confirm text/checkbox stay aligned.
- Close/reopen and confirm no task text drift.

## Tables
- Insert table and edit long text in cells; verify text wraps before pushing columns.
- Run table actions: add/delete row, add/delete column, merge/split, delete table.
- Close/reopen and confirm table structure remains valid.

## Images
- Drag an image into note and verify it renders.
- Resize image and verify width persists after reopen.
- Move image with drag handle and confirm drop indicator appears.
- Close/reopen and confirm no stray `\` lines appear.
- Center an image (select paragraph, apply center alignment), close/reopen, and confirm centering persists.

## Text Alignment Persistence
- Create centered text paragraph, close/reopen, confirm alignment persists.
- Create centered paragraph with image, close/reopen, confirm both image and alignment persist.
- Create numbered list items in a centered paragraph, close/reopen multiple times, confirm no backslash accumulation (e.g., `1\\\\.` growing).

## Focus and Hotkeys
- With inline editor open, verify `Option+Tab` still cycles windows.
- Close inline editor (Escape or back button) and verify `Option+Tab` still works.
- Verify inline editor does not trigger hidden command palette key handlers.
- Verify opening a note from Home, folder view, search, and saved view tabs all work correctly.
- Verify Escape closes editor and returns to previous view (not just clears selection).

## Search
- Search by note title from command palette and open matching note.
- Search by sentence fragment from note body and verify note appears.
- Confirm note search result shows contextual snippet containing match.
- In-note find (`Cmd+F`) focuses instantly, highlights matches, and navigates with up/down.
