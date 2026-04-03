# Canvas Detail Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the right-pinned canvas detail overlay with a centered floating modal matching the NSPanel's `DetailSlideOutView` split layout.

**Architecture:** Full rewrite of `CanvasDetailOverlay.swift` — centered modal with backdrop, toolbar, hero column (left), and metadata sidebar (right). Parent `CanvasWindowContentView.swift` updated to wrap the overlay in a backdrop dismiss layer. All design tokens from existing constants.

**Tech Stack:** SwiftUI, AppKit (`NSVisualEffectView`, `NSPasteboard`, `NSWorkspace`)

**Spec:** `Docs/superpowers/specs/2026-04-01-canvas-detail-modal-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift` | Rewrite | Centered modal: backdrop + toolbar + hero + metadata sidebar |
| `Sources/Cider/Views/Canvas/CanvasWindowContentView.swift` | Modify (lines 34-38) | Remove old transition/positioning, use new centered overlay with backdrop |

---

### Task 1: Rewrite CanvasDetailOverlay — modal shell with backdrop and toolbar

**Files:**
- Rewrite: `Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift`

This task builds the outer shell: backdrop, modal container with acrylic background, and toolbar. No content yet — just the frame.

- [ ] **Step 1: Replace the entire file with the modal shell**

Replace all of `CanvasDetailOverlay.swift` with:

```swift
import SwiftUI

/// Centered floating detail modal over the canvas.
/// Split layout: hero content (left) + metadata sidebar (right).
struct CanvasDetailOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    // MARK: - Layout Constants

    private static let modalWidth: CGFloat = 800
    private static let minHeight: CGFloat = 400
    private static let sidebarWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Modal
            modalContent
                .frame(width: Self.modalWidth, height: modalHeight)
                .background { modalBackground }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                        .allowsHitTesting(false)
                }
                .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
        }
    }

    // MARK: - Modal Content

    @ViewBuilder
    private var modalContent: some View {
        if let selectedID = viewModel.selectedItemID,
           let uuid = UUID(uuidString: selectedID) {
            VStack(spacing: 0) {
                toolbar(for: uuid)

                Divider()
                    .background(CiderColors.separator)
                    .padding(.leading, Spacing.md + Spacing.xxs)

                // Split content area
                HStack(spacing: 0) {
                    heroColumn(for: uuid)

                    // Vertical separator
                    Rectangle()
                        .fill(CiderColors.separator)
                        .frame(width: 1)

                    metadataSidebar(for: uuid)
                        .frame(width: Self.sidebarWidth)
                        .background(CiderColors.surfaceInput)
                }
            }
        } else {
            unknownItemPlaceholder
        }
    }

    // MARK: - Helpers

    private var modalHeight: CGFloat {
        let target = canvasSize.height * 0.8
        let maxH = canvasSize.height - Spacing.xxl * 2
        return min(max(target, Self.minHeight), maxH)
    }

    private var modalBackground: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
            CiderColors.acrylicOverlayTint
            CiderColors.surfaceSubtle
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            onDismiss()
        }
    }

    private var unknownItemPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: Spacing.xxxl))
                .foregroundColor(CiderColors.tertiary)
            Text("Item not found")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Add the toolbar**

Add below the `unknownItemPlaceholder` closing brace, before the final `}` of the struct:

```swift
    // MARK: - Toolbar

    private func toolbar(for uuid: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Title + domain
            toolbarTitle(for: uuid)

            Spacer(minLength: 0)

            // Actions (bookmark-only)
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                toolbarActions(for: bookmark)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.xs + 1)
    }

    @ViewBuilder
    private func toolbarTitle(for uuid: UUID) -> some View {
        if let bookmark = viewModel.bookmarkLookup[uuid] {
            VStack(alignment: .leading, spacing: 0) {
                Text(bookmark.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if bookmark.hasURL {
                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }
        } else if let note = viewModel.noteLookup[uuid] {
            Text(note.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        } else if let todo = viewModel.todoLookup[uuid] {
            Text(todo.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
    }

    private func toolbarActions(for bookmark: Bookmark) -> some View {
        HStack(spacing: Spacing.xs) {
            // Copy URL
            if bookmark.hasURL {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(bookmark.urlString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy URL")
            }

            // Open in browser
            if let url = bookmark.url {
                Button {
                    openURLSafely(url)
                } label: {
                    Image(systemName: "safari")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Browser")
            }
        }
    }
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -20`

This will fail because `heroColumn` and `metadataSidebar` don't exist yet. That's expected — we add them in Task 2.

- [ ] **Step 4: Add stub hero and metadata methods to make it compile**

Add after the toolbar section:

```swift
    // MARK: - Hero Column (Left)

    @ViewBuilder
    private func heroColumn(for uuid: UUID) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Sidebar (Right)

    @ViewBuilder
    private func metadataSidebar(for uuid: UUID) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 5: Verify it compiles**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -20`

Expected: Build succeeds (or fails only on unrelated warnings). The modal shell is in place.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift
git commit -m "feat(canvas): rewrite detail overlay as centered modal shell"
```

---

### Task 2: Wire modal into CanvasWindowContentView with backdrop

**Files:**
- Modify: `Sources/Cider/Views/Canvas/CanvasWindowContentView.swift` (lines 9-42)

- [ ] **Step 1: Update the body to use GeometryReader and new overlay pattern**

In `CanvasWindowContentView.swift`, replace the body (lines 9-42, from `var body: some View {` through the closing brace of the `.animation` modifier for `sidebarVisible`):

```swift
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                NativeCanvasView(viewModel: viewModel)
                    .frame(minWidth: 400, minHeight: 300)

                CanvasSidebarOverlay(
                    isVisible: $sidebarVisible,
                    zoomLevel: viewModel.viewport.zoom,
                    onCollapse: {
                        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                            sidebarVisible = false
                        }
                    },
                    onSelectFolder: { folderID in
                        guard let folderID else { return }
                        viewModel.panToFolder(folderID)
                    }
                )

                // Collapsed pill — shows when sidebar is hidden
                if !sidebarVisible {
                    collapsedPill
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                }

                // Detail modal with backdrop
                if viewModel.selectedItemID != nil {
                    CanvasDetailOverlay(
                        viewModel: viewModel,
                        canvasSize: geometry.size,
                        onDismiss: { viewModel.deselectAll() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: viewModel.selectedItemID)
            .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: sidebarVisible)
        }
```

Note: The rest of the view (keyboard shortcuts, onChange) stays the same — only the body's top-level and the detail overlay block changed. The `GeometryReader` wraps everything so we can pass `geometry.size` to the modal.

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -20`

Expected: Build succeeds. The modal appears centered with a backdrop when a card is selected.

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Canvas/CanvasWindowContentView.swift
git commit -m "feat(canvas): wire centered detail modal with backdrop dismiss"
```

---

### Task 3: Implement hero column content

**Files:**
- Modify: `Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift`

Replace the stub `heroColumn` with real content for each item type.

- [ ] **Step 1: Replace the heroColumn stub**

Replace the `heroColumn` method (the stub from Task 1 Step 4) with:

```swift
    // MARK: - Hero Column (Left)

    @ViewBuilder
    private func heroColumn(for uuid: UUID) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                bookmarkHero(bookmark)
            } else if let note = viewModel.noteLookup[uuid] {
                noteHero(note)
            } else if let todo = viewModel.todoLookup[uuid] {
                todoHero(todo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    // MARK: - Bookmark Hero

    private func bookmarkHero(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title
            Text(bookmark.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Domain with favicon
            if bookmark.hasURL {
                HStack(spacing: Spacing.xs) {
                    if let host = bookmark.url?.host {
                        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(host)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .frame(width: Spacing.lg, height: Spacing.lg)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                            default:
                                Image(systemName: "globe")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                        }
                    }
                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }
            }

            // Thumbnail hero
            if let thumbnailURL = bookmark.thumbnailFileURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .shadow(
                                color: CiderColors.shadowMedium,
                                radius: BookmarksDesign.detailsFloatingLiftBlur,
                                x: 0,
                                y: BookmarksDesign.detailsFloatingLiftYOffset
                            )
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // Fallback letter icon
                bookmarkFallbackHero(bookmark)
            }
        }
    }

    private func bookmarkFallbackHero(_ bookmark: Bookmark) -> some View {
        let letter = bookmark.title.first.map(String.init) ?? "?"
        return RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(CiderColors.surfaceInput)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .overlay {
                Text(letter)
                    .font(.system(size: BookmarksDesign.detailsHeroFallbackLetterSize, weight: .bold, design: .rounded))
                    .foregroundColor(CiderColors.tertiary)
            }
    }

    // MARK: - Note Hero

    private func noteHero(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(note.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            let preview = note.contentPreview
            if !preview.isEmpty {
                Text(preview)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Todo Hero

    private func todoHero(_ todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title with completion indicator
            HStack(spacing: Spacing.sm) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(todo.isCompleted ? CiderColors.success : CiderColors.tertiary)

                Text(todo.title)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(3)
                    .strikethrough(todo.isCompleted)
                    .textSelection(.enabled)
            }

            // Priority
            if let priority = todo.priority {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: priority.icon)
                        .font(CiderFont.caption)
                        .foregroundColor(priority.color)
                    Text(priority.displayName + " Priority")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(priority.color)
                }
            }

            // Details
            if !todo.details.isEmpty {
                Text(todo.details)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }

            // Checklist
            if !todo.checklist.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Checklist (\(todo.completedCount)/\(todo.totalCount))")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(todo.checklist) { item in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .font(CiderFont.body)
                                .foregroundColor(item.isCompleted ? CiderColors.success : CiderColors.tertiary)

                            Text(item.title)
                                .font(CiderFont.body)
                                .foregroundColor(item.isCompleted ? CiderColors.tertiary : CiderColors.primary)
                                .strikethrough(item.isCompleted)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift
git commit -m "feat(canvas): implement hero column for detail modal"
```

---

### Task 4: Implement metadata sidebar

**Files:**
- Modify: `Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift`

Replace the stub `metadataSidebar` with real metadata content for each item type.

- [ ] **Step 1: Replace the metadataSidebar stub**

Replace the `metadataSidebar` method (the stub from Task 1 Step 4) with:

```swift
    // MARK: - Metadata Sidebar (Right)

    private func metadataSidebar(for uuid: UUID) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let bookmark = viewModel.bookmarkLookup[uuid] {
                    bookmarkMetadata(bookmark)
                } else if let note = viewModel.noteLookup[uuid] {
                    noteMetadata(note)
                } else if let todo = viewModel.todoLookup[uuid] {
                    todoMetadata(todo)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bookmark Metadata

    private func bookmarkMetadata(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Folder
            if let folderID = bookmark.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !bookmark.labelIDs.isEmpty {
                labelPills(for: bookmark.labelIDs)
            }

            // AI Summary
            if let summary = bookmark.aiSummary, !summary.isEmpty {
                metadataSection(title: "Summary") {
                    Text(summary)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            // Notes
            if !bookmark.notes.isEmpty {
                metadataSection(title: "Notes") {
                    Text(bookmark.notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // Created date
            metadataRow(
                icon: "calendar",
                label: "Added",
                value: bookmark.createdAt.noteCardDate
            )

            // Open in Browser
            if bookmark.hasURL, let url = bookmark.url {
                Button {
                    openURLSafely(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "safari")
                        Text("Open in Browser")
                    }
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Note Metadata

    private func noteMetadata(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Folder
            if let folderID = note.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !note.labelIDs.isEmpty {
                labelPills(for: note.labelIDs)
            }

            // Word count
            let wordCount = note.wordCount
            if wordCount > 0 {
                metadataRow(icon: "textformat.abc", label: "Words", value: "\(wordCount)")
            }

            Divider()

            // Modified date
            metadataRow(
                icon: "calendar",
                label: "Modified",
                value: note.modifiedAt.noteCardDate
            )
        }
    }

    // MARK: - Todo Metadata

    private func todoMetadata(_ todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Due date
            if let dueDate = todo.dueDate {
                metadataRow(icon: "clock", label: "Due", value: dueDate.noteCardDate)
            }

            // Folder
            if let folderID = todo.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !todo.labelIDs.isEmpty {
                labelPills(for: todo.labelIDs)
            }

            Divider()

            // Created date
            metadataRow(
                icon: "calendar",
                label: "Created",
                value: todo.createdAt.noteCardDate
            )
        }
    }

    // MARK: - Shared Components

    private func metadataSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            content()
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.lg)

            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            Spacer()

            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
        }
    }

    private func labelPills(for labelIDs: [UUID]) -> some View {
        let labels = labelIDs.compactMap { id in
            labelStorage.labels.first { $0.id == id }
        }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Tags")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(labels) { label in
                    let fillColor = Color(hex: label.colorHex) ?? CiderColors.controlAccent
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(fillColor)
                            .frame(width: Spacing.sm, height: Spacing.sm)
                        Text(label.name)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.primary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
            }
        }
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -20`

Expected: Build succeeds. Full modal is now functional.

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Canvas/CanvasDetailOverlay.swift
git commit -m "feat(canvas): implement metadata sidebar for detail modal"
```

---

### Task 5: Final build verification and push

- [ ] **Step 1: Full build**

Run: `cd /Users/minivish/Cider && swift build -Xswiftc -warnings-as-errors 2>&1 | tail -30`

Expected: Clean build with no errors.

- [ ] **Step 2: Push**

```bash
git push origin feature/native-canvas
```
