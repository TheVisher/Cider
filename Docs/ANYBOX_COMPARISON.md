# Anybox vs Cider (Comparison + Raycast Plan)

Last updated: February 17, 2026

## Executive Summary

Anybox and Cider overlap on bookmark capture and retrieval, but they are not identical products:

- **Anybox** is strongest as a mature bookmark/read-later manager with polished automation and integration surfaces.
- **Cider** is strongest as an active, mixed-content workspace (bookmarks + notes + folders + projects + search tabs) with a floating panel workflow.

Positioning recommendation:

- **Anybox = archive/manager**
- **Cider = active research/workbench companion**

## Where Cider Is Differentiated

These are implemented in Cider today:

- Mixed workspace model across Home, Bookmarks, Notes, Search tabs, and Project tabs:
  - `Sources/Cider/Views/CiderPanelView.swift`
  - `Sources/Cider/Models/CiderTab.swift`
  - `Sources/Cider/Views/Search/SearchTabContent.swift`
  - `Sources/Cider/Services/ProjectStorage.swift`
- Local-first note system with markdown files on disk, folder assignment, file watching, and snapshots/history:
  - `Sources/Cider/Services/NotesStorage.swift`
- Cross-browser active-tab capture with layered fallback strategy (AppleScript, Accessibility traversal, address-bar copy fallback):
  - `Sources/Cider/Services/ActiveBrowserCaptureService.swift`
- Companion-panel + global hotkey workflow:
  - `Option+B` / `Option+Shift+B` in `Sources/Cider/Services/BookmarksHotkeyDetector.swift`
  - `Option+N` in `Sources/Cider/Services/NotesHotkeyDetector.swift`

## Where Anybox Appears Stronger Today

From Anybox public docs + Raycast extension source:

- Mature automation surface:
  - URL schemes
  - AppleScript
  - local API
  - Shortcuts-style commandability
  - published Raycast extension
- Polished capture ecosystem around Quick Save / current-tab save / clipboard save and Anydock/Stashbox controls.
- Read-later/bookmark-manager depth is more mature and productized today.
- Mobile/cross-device story is clearer publicly.

## Practical Product Positioning for Cider

To avoid being seen as “Anybox clone,” emphasize:

- Project-oriented workflows over static archiving.
- Mixed bookmark + note workflows as a core primitive.
- Floating panel as a “live companion” while browsing/working.
- Search-to-project lifecycle (`Search -> Tab -> Project -> Folder/Archive`) from `Docs/WORKSPACES_VISION.md`.

## Raycast Extension for Cider (How to Build It)

### Recommended Architecture

Use the same successful pattern seen in Anybox’s Raycast integration:

1. **Raycast command** triggers action.
2. Command calls **local HTTP API in Cider** (`127.0.0.1`, localhost only).
3. Cider performs action and returns JSON response.

This gives low-latency local control and keeps Cider as the source of truth.

### Cider API Surface (v1)

Implement minimal endpoints first:

- `POST /panel/toggle`
- `POST /bookmarks/capture-active-tab`
- `POST /bookmarks/save`
- `POST /notes/save`
- `GET /search?q=...`
- `GET /folders`
- `GET /projects`

Security:

- Bind to `127.0.0.1` only.
- Require bearer token (`Authorization: Bearer <token>`).
- Store token in Cider settings + Raycast extension preferences.

### Raycast Commands (v1)

Start with:

- `Toggle Cider` (`no-view`)
- `Save Current Tab` (`no-view`)
- `Save Clipboard URL` (`no-view`)
- `Quick Note` (`view`, form)
- `Search Cider` (`view`, list/grid)

Then expand:

- `Save Current Tab with Folder`
- `Save Current Tab with Tags`
- `Save Clipboard with Folder/Tags`
- `Open Project`

### Current Tab Capture Strategy

Two viable approaches:

- **Primary**: call Cider’s own capture endpoint (`/bookmarks/capture-active-tab`) and reuse current Cider capture logic.
- **Optional optimization**: Raycast Browser Extension API (`getActiveTab`) where available, then `POST /bookmarks/save`.

### Example Request Shape

```ts
await fetch("http://127.0.0.1:6392/bookmarks/capture-active-tab", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${apiToken}`,
    "Content-Type": "application/json",
  },
});
```

### Implementation Checklist

1. Add URL/API integration phase to active roadmap execution.
2. Implement Cider local API server and token management.
3. Add first three no-view Raycast commands.
4. Add `Search Cider` list command.
5. Add graceful “Cider not running” handling in extension.
6. Test matrix:
   - Cider running/stopped
   - token missing/invalid
   - browser capture permission states
7. Publish extension after `ray lint` and `ray build`.

## Existing Cider Roadmap Alignment

This is already documented in Cider planning:

- `Docs/INTEGRATION_DESIGN.md` includes:
  - URL scheme placeholder (`cider://capture`, `cider://search`, `cider://show`)
  - Raycast extension placeholder

## Sources

Anybox + Raycast:

- https://anybox.app/
- https://anybox.app/getting-started/
- https://anybox.app/faq/
- https://anybox.app/url-schemes/
- https://anybox.app/applescript/
- https://anybox.app/singlefile/
- https://www.raycast.com/francisfeng/anybox
- https://raw.githubusercontent.com/raycast/extensions/ad9f7d6a489332bc17d8428f602e507884b2f652/extensions/anybox/README.md
- https://raw.githubusercontent.com/raycast/extensions/ad9f7d6a489332bc17d8428f602e507884b2f652/extensions/anybox/package.json
- https://raw.githubusercontent.com/raycast/extensions/ad9f7d6a489332bc17d8428f602e507884b2f652/extensions/anybox/src/utilities/fetch.tsx
- https://raw.githubusercontent.com/raycast/extensions/ad9f7d6a489332bc17d8428f602e507884b2f652/extensions/anybox/src/utilities/searchRequest.tsx

Raycast developer docs:

- https://developers.raycast.com/getting-started/create-your-first-extension
- https://developers.raycast.com/information/manifest
- https://developers.raycast.com/api-reference/browser-extension
- https://developers.raycast.com/api-reference/browser-extension/get-active-tab
