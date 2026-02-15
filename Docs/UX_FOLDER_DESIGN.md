# UX Insight: Folder Design & Future Enhancements

> Captured during folder sidebar implementation (Feb 2026)

## Current Design: Root Folders as Group Headers

Root folders act as category headers (inspired by Dia browser tab groups):

- **No chevron** — clicking the root selects it AND expands/collapses children
- **Icon transition** — folder icon briefly becomes a chevron on click, reverts after 1.5s
- **Hover reveal** — hovering an expanded root shows the chevron again
- **Sub-folders** below the root are indented with standard chevrons

### Content Model

When a root folder is selected, the content area shows:
1. **Sub-folder cards** — grid of child folders (like Finder icon view), click to drill in
2. **Unsorted items** — bookmarks/notes assigned directly to the root (inbox/catch-all)

This makes roots both a **navigation hub** and an **inbox** for quick-dump sorting.

## Future: Custom Folder Image Headers

Each root folder (and potentially sub-folders) could have a custom image header:
- A banner/hero image at the top of the folder overview
- Adds visual personality and quick recognition to each category
- Could be set via right-click > "Set Cover Image" or drag-and-drop
- Falls back to a colored gradient or pattern when no image is set

### Implementation Ideas

- Store image path/data in `Folder` model (new `coverImageData: Data?` field)
- Show as a short banner (80-120pt) at the top of `RootFolderOverviewView`
- Rounded corners, slight overlay gradient for text readability
- Consider supporting unsplash-style random images as defaults

## Future: Custom Folder Icons

Allow users to change the folder icon in the sidebar:
- Right-click > "Change Icon" on any folder row
- Pick from SF Symbols or emoji
- Store as `iconName: String?` in `Folder` model
- Default to "folder.fill" for roots, "folder" for sub-folders
