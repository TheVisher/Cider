# Clipboard Vision

## Current State

Standalone `ClipboardPanel` — a dedicated NSPanel that opens/closes independently via Opt+V. The Cider panel is never touched. Clipboard history is managed by `ClipboardHistoryService` and stored in `ClipboardStorage`.

## Future Enhancements

### Toast-to-Clipboard Morphing

When something is copied, the capture toast shows a preview of the item. Hovering the toast expands/transitions it into the full clipboard panel with that item at the top. The toast becomes a gateway into clipboard history rather than just a notification.

**Flow:**
1. User copies something → small toast appears with item preview
2. Toast auto-dismisses after timeout (normal behavior)
3. If user hovers the toast → toast morphs/expands into the full clipboard panel
4. The copied item is highlighted at the top of the clipboard history
5. User can interact with clipboard history, copy other items, save to bookmarks/notes

**Design considerations:**
- Toast position should align with where the clipboard panel will appear
- Morphing animation: toast grows in place, content cross-fades from toast preview to full clipboard UI
- If clipboard panel is already open, toast should just flash the new item at the top instead of morphing
