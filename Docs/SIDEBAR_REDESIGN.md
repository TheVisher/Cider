# Sidebar Redesign

> **Status: Implemented.** Absorb into DESIGN_SYSTEM.md and SHARED_COMPONENTS.md, then delete this file.
>
> **Deviations from original plan:**
> - Sidebar keeps its floating rounded-rect look with padding (like Messages) — not a flush integrated column
> - View options button lives in the sidebar header (right of traffic lights), not as a content area overlay
> - No vertical divider line between sidebar and content — the sidebar's rounded border provides separation
> - FolderSidebarView has `showBackground: Bool` param — when `false`, the wrapper handles the background
> - Sidebar header has fixed 28pt height to prevent content shift when switching tabs
> - Title bar divider is inset horizontally (`padding(.horizontal, Spacing.md)`)

## Goal

Redesign the main app sidebar from a nested content-area element to a full-height structural column, matching modern chat/productivity apps like Messenger. This becomes the shared sidebar pattern reused by the standalone notes panel.

---

## Current Layout

```
CiderPanelView
┌─────────────────────────────────────────┐
│ [traffic lights] [sidebar] [tabs...] [+]│  ← title bar (40pt)
├─────────────────────────────────────────┤
│ ┌──────────┐ ┌────────────────────────┐ │
│ │ Sidebar  │ │                        │ │
│ │ (224pt)  │ │    Content area        │ │
│ │          │ │                        │ │
│ └──────────┘ └────────────────────────┘ │
└─────────────────────────────────────────┘
```

- Sidebar sits inside the content area, below the title bar
- Traffic lights are in the title bar, always visible
- Tabs fill the title bar horizontally
- Sidebar toggle button sits between traffic lights and tabs

## New Layout

```
CiderPanelView
┌──────────┬──────────────────────────────┐
│ Traffic  │ [tabs...]           [options]│  ← title bar
│ lights   ├──────────────────────────────┤
│          │                              │
│ Sidebar  │         Content area         │
│ (full    │                              │
│  height) │                              │
│          │                              │
│          │                              │
└──────────┴──────────────────────────────┘
```

### Key Changes

1. **Sidebar runs full panel height** — not nested under the title bar. It's a top-level HStack peer with the right column (title bar + content).

2. **Traffic lights move into the sidebar header** — positioned at the top of the sidebar column, vertically aligned with the title bar. When the sidebar is visible, traffic lights live there.

3. **Traffic lights hidden when sidebar collapsed** — when the sidebar is toggled off, the traffic lights disappear. They're part of the sidebar surface, not the title bar.

4. **Right-click context menu on title bar** — since traffic lights can be hidden, provide a universal right-click menu on the title bar with Close, Minimize, and Maximize options as a fallback.

5. **Tabs shift right** — the tab bar no longer shares horizontal space with traffic lights. It fills the right column's title bar area completely.

6. **View options move to top-right** — the view options button (display mode + card size slider) moves from the title bar to the top-right corner of the content area, keeping the title bar clean.

7. **Sidebar toggle stays in title bar** — the sidebar toggle button remains in the right column's title bar (leftmost position), so users can always show/hide the sidebar.

---

## Sidebar Header (New)

The top of the sidebar column (aligned with the title bar height) contains:
- **Traffic light buttons** — close (red), minimize (yellow), maximize (green)
- Vertically centered within the 40pt title bar height
- Same custom `CiderTrafficLightButton` components, just repositioned

Below the header, the rest of the sidebar content is unchanged:
- Search trigger
- Folder tree
- Projects section
- Footer (settings + create menu)

---

## Collapsed State

When the sidebar is collapsed:
- The sidebar column is removed from the layout (0 width)
- Traffic lights are hidden — no longer visible anywhere
- Right-click on title bar provides window control fallback
- Sidebar toggle button in the title bar is the only way to bring it back
- Compact mode overlay behavior stays the same (sidebar slides over content below 680pt)

---

## Right-Click Context Menu

Available on the title bar area (right column):
- **Close** — dismiss panel
- **Minimize** — collapse to title bar
- **Maximize** — fill screen

This ensures window controls are always accessible even when traffic lights are hidden with the sidebar collapsed.

---

## Responsive Behavior

The existing compact mode logic (< 680pt threshold) stays the same:
- Below threshold: sidebar auto-collapses, appears as overlay
- Above threshold: sidebar shown side-by-side
- Auto-collapse/expand tracking via `sidebarAutoCollapsed` flag

---

## Component Hierarchy (New)

```
CiderPanelView
├── AcrylicPanelBackground
├── HStack(spacing: 0)                    ← NEW: top-level split
│   ├── SidebarColumn (if visible)         ← NEW: full-height sidebar
│   │   ├── SidebarHeader (40pt)           ← NEW: traffic lights
│   │   │   └── Traffic light buttons
│   │   ├── Divider
│   │   └── FolderSidebarView (existing)
│   └── VStack(spacing: 0)                ← right column
│       ├── titleBar (40pt)
│       │   ├── Sidebar toggle button
│       │   ├── CiderTabBar (fills space)
│       │   └── Capture button (contextual)
│       ├── Divider
│       └── ContentArea
│           ├── View options (top-right overlay)
│           └── Tab content (Home/Bookmarks/Notes)
├── PanelEdgeResizeView
└── SearchPaletteView (overlay)
```

---

## Implementation Notes

- The sidebar column needs its own background treatment — either shared acrylic or a slightly different tint to visually separate it from the content area
- The divider between sidebar and content should be a vertical `Color.white.opacity(0.2)` line matching existing divider style
- Sidebar width stays at 224pt (existing `BookmarksDesign.folderSidebarWidth`)
- Title bar height stays at 40pt
- The sidebar toggle animation (`.snappy`) stays the same — sidebar slides in/out from the left
- This is a prerequisite for the standalone notes panel sidebar (NOTES_VISION.md)
