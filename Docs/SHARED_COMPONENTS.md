# Shared Components & Cross-Tab Patterns

When building a new feature, check this doc first. If a component or pattern already exists, reuse it. If a new feature creates something that could benefit other tabs, add it here.

---

## Shared Views (`Views/Shared/`)

### MasonryLayout
- **File:** `Views/Shared/MasonryLayout.swift`
- **Used by:** Bookmarks, Notes
- **What:** Custom SwiftUI `Layout` that arranges items in a variable-height masonry grid with shortest-column placement
- **Config:** `minimumColumnWidth` and `itemSpacing` — column count auto-calculates from available width

### ViewOptionsDropdown
- **File:** `Views/Shared/ViewOptionsDropdown.swift`
- **Used by:** Bookmarks, Notes (sidebar header popover in CiderPanelView)
- **What:** Generic dropdown for display mode toggle (list/grid/masonry icons) + continuous card size slider
- **Pattern:** Generic over `DisplayModeOption` protocol — any tab with display modes can use it by conforming its enum

### FolderSidebarView
- **File:** `Views/Shared/FolderSidebarView.swift`
- **Used by:** All tabs (universal sidebar in CiderPanelView)
- **What:** Hierarchical folder tree + projects list + search trigger + quick action buttons
- **Params:** `showBackground: Bool = true` — set `false` when a wrapper provides the background (e.g., CiderPanelView's sidebar column)
- **Note:** Folders are shared across bookmarks and notes — both content types can be assigned to any folder

### FolderContentView / RootFolderOverviewView
- **Files:** `Views/Shared/FolderContentView.swift`, `Views/Shared/RootFolderOverviewView.swift`
- **Used by:** CiderPanelView (when a folder is selected in sidebar)
- **What:** Mixed-content views showing bookmarks + notes within a folder

### AcrylicPanelBackground
- **File:** `Views/Shared/AcrylicPanelBackground.swift`
- **Used by:** All panels
- **What:** Standard dark acrylic background with optional custom shadows, respects accessibility transparency

### CiderTabBar
- **File:** `Views/Shared/CiderTabBar.swift`
- **Used by:** CiderPanelView
- **What:** Horizontal scrollable tab bar with badge counts

### CiderPanelShell
- **File:** `Views/Shared/CiderPanelShell.swift`
- **Used by:** CiderPanelView, BookmarksPanelView, NotesPanelView
- **What:** Generic structural shell for all panel windows — encapsulates two-column layout, sidebar container, traffic lights, title bar, divider, compact mode logic, resize handles, and shadow padding
- **Generic params:** `SidebarContent`, `SidebarFooter`, `TitleBarContent`, `Content`, `PanelOverlay`
- **Init params:** `isCollapsed`, `onClose`, `onCollapse`, `onMaximize`, plus `@ViewBuilder` closures for each generic slot
- **Handles:** Sidebar show/hide animation, compact mode auto-collapse at `CiderPanelDesign.sidebarCompactThreshold` (680pt), title bar toggle appearance, panel edge resize, acrylic background + shadow

### PanelEdgeResizeView
- **File:** `Views/Shared/PanelEdgeResizeView.swift`
- **Used by:** CiderPanelView
- **What:** All-edge resize handles with cursor tracking

### EmptyStateView
- **File:** `Views/Shared/EmptyStateView.swift`
- **Used by:** NotesTabContent, NotesPanelView, SearchTabContent, ProjectTabContent, FolderContentView, RootFolderOverviewView
- **What:** Vertically centered empty state with icon (36pt), title, optional subtitle, optional action button
- **Params:** `icon: String`, `title: String`, `subtitle: String?`, `actionLabel: String?`, `action: (() -> Void)?`
- **Note:** BookmarksBrowserView has its own inline empty state that scales with `textScale` — don't use this shared component there

---

## Shared Utilities (`Utilities/`)

### HighlightedText
- **File:** `Utilities/HighlightedText.swift`
- **Used by:** Notes cards/rows (titles and previews)
- **What:** SwiftUI `Text` view with search match highlighting — preserves all Text modifiers (font, color, lineLimit)
- **Reuse opportunity:** Bookmark cards, search results, any list with filtering

### CiderFont
- **File:** `Utilities/CiderFont.swift`
- **Used by:** All views with text
- **What:** Semantic typography tokens replacing all `.font(.system(size:weight:))` declarations. 29 fixed tokens + 13 responsive `(scale:)` function variants for textScale views.
- **Pattern:** `CiderFont.body`, `CiderFont.captionMedium`, `CiderFont.subheadingSemibold`, etc.
- **Responsive:** `CiderFont.body(scale: textScale)` for views with continuous card size slider
- **When NOT to use:** Design constants (`CiderPanelDesign.trafficLightSymbolSize`), dynamic weights (`isSelected ? .semibold : .regular`), Apple semantic styles in Settings views

### Constants (Spacing, Radius, Animation)
- **File:** `Utilities/Constants.swift`
- **What:** All design tokens — `Spacing.*`, `Radius.*`, animation presets, notification names, border constants

### VisualEffectView
- **File:** `Utilities/VisualEffectView.swift`
- **What:** NSViewRepresentable for `NSVisualEffectView` — use instead of `.glassEffect()`

---

## Cross-Tab Patterns

These aren't single components but established patterns that should be followed consistently across tabs.

### Display Modes (list / grid / masonry)
- **Used by:** Bookmarks (`BookmarkDisplayMode`), Notes (`NoteDisplayMode`)
- **Pattern:** Enum conforming to `DisplayModeOption` protocol → plugs into `ViewOptionsDropdown`
- **Card sizing:** Continuous 0–3 slider via a sizing struct (e.g., `CardSizing`, `NoteCardSizing`) that interpolates between stops
- **When adding a new tab with cards:** Create a `<Tab>DisplayMode` enum conforming to `DisplayModeOption` + a `<Tab>CardSizing` struct

### Card Data Loading
- **Used by:** Notes (`NoteCardData`)
- **Pattern:** Pre-compute display data off the main thread, cache in `@State`
- **Key rule:** Use `.task(id: item.modifiedAt)` not `.task(id: item.id)` so cards refresh after edits
- **Never:** Put disk I/O or regex in SwiftUI view body — always use `.task` + `@State` cache

### CardContextMenu (NSMenu-based)
- **File:** `Utilities/CardContextMenu.swift`
- **Used by:** Notes (NoteCardView, NoteListRow), Bookmarks (BookmarkCard, BookmarkListRow)
- **What:** Native `NSMenu` context menu that builds fresh on every right-click, replacing SwiftUI's `.contextMenu` which caches content and goes stale when data changes
- **Architecture:** `CardMenuItem` enum (.action, .submenu, .separator, .destructive) → `CardContextMenuModifier` → invisible `RightClickView` overlay with `hitTest` pass-through for non-right-click events
- **Convenience extensions:** `.noteContextMenu()` (Open, Rename, Move to Folder, Delete) and `.bookmarkContextMenu()` (Open in Browser, Show Details, Move to Folder, Delete)
- **Adding a new context menu:** Create a new View extension that returns `CardContextMenuModifier` with the desired `CardMenuItem` list
- **Key detail:** `RightClickView.hitTest()` returns nil for non-right-click events so left clicks, hovers, and drags pass through to SwiftUI content underneath
- **Why not `.contextMenu`:** SwiftUI caches `.contextMenu` content inside lazy containers (`LazyVStack`, `LazyVGrid`). After any data change (moving items to folders, creating folders), the menu shows stale content. No workaround (`.id()`, removing conditionals) reliably fixes it.

### Container Style Modifiers
- **File:** `Utilities/ContainerStyles.swift`
- **Used by:** CiderPanelShell, BookmarksBrowserView, RootFolderOverviewView, NoteCardView
- **What:** Two `ViewModifier`s for common container background + border patterns
- **Modifiers:**
  - `.sectionContainer(cornerRadius:)` — static elevated container: `surfaceElevated` fill + `borderDefault` stroke + `innerStrokeWidth`. Default radius: `Radius.md`. For sidebar columns, panel sections, folder cards.
  - `.cardContainer(isHovered:, cornerRadius:)` — hover-aware card: `surfaceElevated`/`surfaceHover` fill + `borderSubtle`/`borderHover` stroke + clipShape + contentShape. Default radius: `BookmarksDesign.cardCornerRadius`. For masonry/grid cards.
- **When NOT to use:** Containers with conditional backgrounds (FolderSidebarView's `showBackground` flag) or cards with custom stroke logic (BookmarksBrowserView's drop-target border)

### Button Styles
- **File:** `Utilities/ButtonStyles.swift`
- **Used by:** Settings views (currently), any view needing pill-shaped action buttons
- **What:** Three shared `ButtonStyle` variants for pill-shaped action buttons with rounded backgrounds and press states
- **Styles:**
  - `CiderAccentButtonStyle` — primary action (accent text on `accentSubtle` bg, `accentLight` on press)
  - `CiderDestructiveButtonStyle` — destructive action (red text on `destructiveSubtle` bg, `destructiveLight` on press)
  - `CiderSecondaryButtonStyle` — cancel/dismiss (secondary text on `surfaceInput` bg, `surfaceHover` on press)
- **All three share:** `.font(CiderFont.body)` + `.padding(.horizontal: Spacing.md, .vertical: Spacing.sm)` + `RoundedRectangle(Radius.sm)` background
- **When NOT to use:** Icon-only toolbar buttons (use `.buttonStyle(.plain)`) or buttons that need `textScale` multipliers (style inline)

### Hover State Modifier
- **File:** `Utilities/HoverState.swift`
- **Used by:** All interactive views with hover effects
- **What:** `.hoverState($isHovered)` — binds hover to a `@State` Bool. Optional `animation:` parameter wraps state change in `withAnimation` with automatic Reduce Motion respect.
- **Usage:**
  - `.hoverState($isHovered)` — plain binding (use when view has `.animation(_, value: isHovered)`)
  - `.hoverState($isHovered, animation: .snappy)` — animated (use when no `.animation()` on view)
- **Remaining `.onHover`:** `BookmarksBrowserView` list row (custom hover callback) and `BookmarkCaptureToastPanel` (toast dismiss logic) — both have custom `onHoverChanged` callbacks, can't use shared modifier

### Inline Rename
- **Used by:** Notes (NoteCardView, NoteListRow)
- **Pattern:** Local `@State isRenaming` + `@State renamingTitle` + `@FocusState` per card
- **Flow:** Context menu "Rename" → title swaps to TextField → Enter saves, Escape cancels
- **Focus:** Use `.task { try? await Task.sleep(for: .milliseconds(150)); focused = true }` — NSPanel needs delay for `@FocusState`
- **Reuse opportunity:** Bookmark cards, folder rename in sidebar

### Folder Assignment
- **Used by:** Notes (via context menu), Bookmarks (via drag-and-drop and context menu)
- **Pattern:** Folders stored in `BookmarksStorage.shared.folders`, shared across all content types
- **Future:** Notes will support drag-to-folder (matching bookmarks) and multi-folder membership (`folderIDs: [UUID]` instead of `folderID: UUID?`)
