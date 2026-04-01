# Native Canvas Phase 2: Performance, Folder Groups & Polish

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix performance bottlenecks, add proper folder group collapse/expand, and polish zoom/drag behavior — proving the native canvas matches the old WebView version.

**Architecture:** Three workstreams that can be tackled independently: (A) Performance fixes from code reviews, (B) Folder group interactivity, (C) UX polish. Each produces testable improvements without blocking the others.

**Tech Stack:** SwiftUI, AppKit (NSEvent monitors), os.Logger, CiderCLI

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Cider/ViewModels/CanvasViewModel.swift` | Modify | Add item lookup dictionaries, split @Published properties |
| `Sources/Cider/Views/Canvas/CanvasCardView.swift` | Modify | Use lookup dictionaries instead of O(n) scans |
| `Sources/Cider/Views/Canvas/CanvasFolderGroupView.swift` | Create | Extracted folder group view with collapse/expand/layout |
| `Sources/Cider/Views/Canvas/NativeCanvasView.swift` | Modify | Remove redundant MagnifyGesture, fix zoom anchor |
| `Sources/Cider/Views/Canvas/CanvasMinimapView.swift` | Modify | Minor: use shared bounding box utility |
| `Sources/Cider/Models/CanvasNode.swift` | Modify | Add folderName field for folder groups |
| `Sources/CiderCLI/CiderCLI.swift` | Modify | Add `canvas collapse`/`canvas expand` commands |

---

### Task 1: Fix O(n) Lookups in CanvasCardView

The biggest performance issue from both reviews. Every visible card does `.first(where:)` on the full bookmarks/notes/todos arrays during `body` evaluation. With 120+ bookmarks visible, that's O(n^2) on every frame.

**Files:**
- Modify: `Sources/Cider/ViewModels/CanvasViewModel.swift`
- Modify: `Sources/Cider/Views/Canvas/CanvasCardView.swift`

- [ ] **Step 1: Add lookup dictionaries to CanvasViewModel**

Add pre-built dictionaries alongside the existing `titleCache`:

```swift
// In CanvasViewModel, after the titleCache property:
@Published private(set) var bookmarkLookup: [UUID: Bookmark] = [:]
@Published private(set) var noteLookup: [UUID: Note] = [:]
@Published private(set) var todoLookup: [UUID: TodoCard] = [:]
```

- [ ] **Step 2: Build lookups in rebuildTitleCache**

Extend the existing `rebuildTitleCache()` method to also populate the lookup dictionaries:

```swift
func rebuildTitleCache() {
    var titles: [String: String] = [:]
    var bmLookup: [UUID: Bookmark] = [:]
    var nLookup: [UUID: Note] = [:]
    var tLookup: [UUID: TodoCard] = [:]

    for bm in VaultBookmarkService.shared.bookmarks {
        titles[bm.id.uuidString] = bm.title
        bmLookup[bm.id] = bm
    }
    for note in NotesStorage.shared.notes {
        titles[note.id.uuidString] = note.title
        nLookup[note.id] = note
    }
    for todo in TodoCardStorage.shared.todoCards {
        titles[todo.id.uuidString] = todo.title
        tLookup[todo.id] = todo
    }
    for folder in VaultFolderService.shared.folders {
        titles["folder-\(folder.id.uuidString)"] = folder.name
    }

    titleCache = titles
    bookmarkLookup = bmLookup
    noteLookup = nLookup
    todoLookup = tLookup
}
```

- [ ] **Step 3: Update CanvasCardView to use lookups**

Replace every `.first(where:)` with dictionary lookup. In `bookmarkCard`:

```swift
if let itemID = node.itemID,
   let uuid = UUID(uuidString: itemID),
   let bookmark = viewModel.bookmarkLookup[uuid] {
```

Same pattern for `noteCard` (use `viewModel.noteLookup[uuid]`) and `todoCard` (use `viewModel.todoLookup[uuid]`).

- [ ] **Step 4: Verify build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep "error:" | grep -E "(CanvasCard|CanvasViewModel)" | head -5`
Expected: no output (clean build)

- [ ] **Step 5: Verify canvas data integrity**

Run: `.build/arm64-apple-macosx/debug/cider-cli canvas validate`
Expected: all checks pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/ViewModels/CanvasViewModel.swift Sources/Cider/Views/Canvas/CanvasCardView.swift
git commit -m "perf: replace O(n) card lookups with dictionary cache in canvas"
```

---

### Task 2: Remove Redundant MagnifyGesture

The `MagnifyGesture` on the outer ZStack is redundant — the NSEvent monitor already handles trackpad pinch-to-zoom with cursor anchoring. The SwiftUI gesture doesn't anchor to cursor and can conflict.

**Files:**
- Modify: `Sources/Cider/Views/Canvas/NativeCanvasView.swift`

- [ ] **Step 1: Remove gestureZoom state and MagnifyGesture**

Remove `@State private var gestureZoom: CGFloat = 1.0` and the `zoomGesture` computed property. Update `effectiveZoom` to just use `currentZoom`:

```swift
private var effectiveZoom: CGFloat {
    min(max(currentZoom, CanvasViewport.minZoom), CanvasViewport.maxZoom)
}
```

Remove `.gesture(zoomGesture)` from the body.

Remove `gestureZoom = 1.0` from `fitToContent`.

- [ ] **Step 2: Verify build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep "error:" | grep "NativeCanvas" | head -5`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Canvas/NativeCanvasView.swift
git commit -m "fix: remove redundant MagnifyGesture (NSEvent monitor handles zoom)"
```

---

### Task 3: Extract CanvasFolderGroupView with Collapse/Expand

The folder group rendering is currently inline in `CanvasCardView.folderGroupPlaceholder`. Extract it to its own view with collapse/expand toggle.

**Files:**
- Create: `Sources/Cider/Views/Canvas/CanvasFolderGroupView.swift`
- Modify: `Sources/Cider/Views/Canvas/CanvasCardView.swift`
- Modify: `Sources/Cider/Models/CanvasNode.swift`
- Modify: `Sources/Cider/ViewModels/CanvasViewModel.swift`

- [ ] **Step 1: Add toggleCollapse to CanvasViewModel**

```swift
func toggleCollapse(nodeID: String) {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    nodes[index].collapsed.toggle()
    scheduleDebouncedSave()
}
```

- [ ] **Step 2: Create CanvasFolderGroupView**

Create `Sources/Cider/Views/Canvas/CanvasFolderGroupView.swift`:

```swift
import SwiftUI

/// Folder group container on the canvas with collapsible header and child card grid.
struct CanvasFolderGroupView: View {
    let node: CanvasNode
    let zoom: CGFloat
    @ObservedObject var viewModel: CanvasViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var folderName: String {
        viewModel.titleCache[node.id] ?? "Folder"
    }

    private var childNodes: [CanvasNode] {
        viewModel.nodes.filter { $0.parentNodeID == node.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — click to collapse/expand
            headerBar

            // Child cards — hidden when collapsed
            if !node.collapsed {
                childGrid
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )
        )
        .frame(width: node.collapsed ? nil : node.size.width)
    }

    // MARK: - Header

    private var headerBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                viewModel.toggleCollapse(nodeID: node.id)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 12)

                Image(systemName: "folder.fill")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.secondary)

                Text(folderName)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("\(childNodes.count)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(CiderColors.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Child Grid

    private var childGrid: some View {
        let columns = min(4, max(1, childNodes.count))
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: columns)

        return LazyVGrid(columns: gridItems, spacing: Spacing.md) {
            ForEach(childNodes) { child in
                CanvasCardView(
                    node: child,
                    zoom: zoom,
                    viewModel: viewModel
                )
            }
        }
    }
}
```

- [ ] **Step 3: Replace folderGroupPlaceholder in CanvasCardView**

In `CanvasCardView.swift`, replace the `folderGroupPlaceholder` computed property:

```swift
@ViewBuilder
private var folderGroupPlaceholder: some View {
    CanvasFolderGroupView(
        node: node,
        zoom: zoom,
        viewModel: viewModel
    )
}
```

Delete all the old inline folder group code (the VStack with header HStack and LazyVGrid).

- [ ] **Step 4: Verify build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep "error:" | grep -E "(CanvasCard|CanvasFolder)" | head -5`
Expected: no output

- [ ] **Step 5: Test collapse via CLI**

Verify the canvas JSON tracks collapsed state:

```bash
.build/arm64-apple-macosx/debug/cider-cli canvas show --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
folders=[n for n in d['nodes'] if n.get('nodeType')=='folderGroup']
for f in folders[:3]:
    m=f.get('metadata',{})
    print(f'{m.get(\"folderName\",\"?\")}: collapsed={m.get(\"collapsed\",False)}')
"
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Canvas/CanvasFolderGroupView.swift Sources/Cider/Views/Canvas/CanvasCardView.swift Sources/Cider/ViewModels/CanvasViewModel.swift
git commit -m "feat: extract CanvasFolderGroupView with collapse/expand toggle"
```

---

### Task 4: Add Collapse/Expand CLI Commands

Let agents and CLI users collapse and expand folders programmatically.

**Files:**
- Modify: `Sources/CiderCLI/CiderCLI.swift`

- [ ] **Step 1: Add collapse and expand subcommands**

In the canvas command switch, before the `default` case, add:

```swift
case "collapse", "expand":
    let shouldCollapse = (subcommand == "collapse")
    guard let folderName = args.first else {
        print("Error: Usage: cider-cli canvas \(subcommand!) <folder-name-or-id>")
        return
    }
    guard var canvas = loadCanvasJSON() else {
        print("Error: No canvas found")
        return
    }
    var nodes = (canvas["nodes"] as? [[String: Any]]) ?? []
    let lowered = folderName.lowercased()

    guard let idx = nodes.firstIndex(where: {
        let nodeType = $0["nodeType"] as? String ?? ""
        guard nodeType == "folderGroup" else { return false }
        let nodeID = ($0["id"] as? String)?.lowercased() ?? ""
        let meta = $0["metadata"] as? [String: Any]
        let name = (meta?["folderName"] as? String)?.lowercased() ?? ""
        return nodeID.contains(lowered) || name.contains(lowered)
    }) else {
        print("Error: Folder '\(folderName)' not found on canvas")
        return
    }

    var node = nodes[idx]
    var meta = (node["metadata"] as? [String: Any]) ?? [:]
    meta["collapsed"] = shouldCollapse
    node["metadata"] = meta
    nodes[idx] = node

    var updated = canvas
    updated["nodes"] = nodes
    saveCanvasJSON(updated)

    let name = (meta["folderName"] as? String) ?? folderName
    print("\(shouldCollapse ? "Collapsed" : "Expanded") folder '\(name)'")
```

Also update the default case help text to include the new commands.

- [ ] **Step 2: Build and test**

```bash
swift build --product cider-cli
.build/arm64-apple-macosx/debug/cider-cli canvas collapse Gaming
.build/arm64-apple-macosx/debug/cider-cli canvas expand Gaming
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CiderCLI/CiderCLI.swift
git commit -m "feat: add canvas collapse/expand CLI commands"
```

---

### Task 5: Folder Group Size Auto-Calculation

Folder group size should be calculated from its children count rather than using the fixed 280x260 default. This ensures folder containers are sized correctly for their content.

**Files:**
- Modify: `Sources/Cider/ViewModels/CanvasViewModel.swift`

- [ ] **Step 1: Add folder size recalculation**

Add a method that recomputes folder group sizes based on child count:

```swift
func recalculateFolderSizes() {
    let columns = 4
    let cardWidth: CGFloat = 280
    let cardGapX: CGFloat = 20
    let cardSpacingX: CGFloat = cardWidth + cardGapX
    let cardHeight: CGFloat = 260
    let cardGapY: CGFloat = 20
    let cardSpacingY: CGFloat = cardHeight + cardGapY
    let folderPadding: CGFloat = 60
    let folderInset: CGFloat = 20

    for i in nodes.indices {
        guard nodes[i].itemType == "folderGroup" else { continue }
        let children = nodes.filter { $0.parentNodeID == nodes[i].id }
        guard !children.isEmpty else { continue }

        let actualColumns = min(columns, max(1, children.count))
        let rows = max(1, (children.count + columns - 1) / columns)
        let width = CGFloat(actualColumns) * cardSpacingX + folderInset * 2
        let height = folderPadding + CGFloat(rows) * cardSpacingY + folderInset + 20

        nodes[i].size = CGSize(width: width, height: height)
    }
}
```

Call this at the end of `loadCanvas()` and `generateInitialLayout()`, before saving.

- [ ] **Step 2: Collapse should shrink the node size**

In `toggleCollapse`, adjust the size:

```swift
func toggleCollapse(nodeID: String) {
    guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
    nodes[index].collapsed.toggle()

    if nodes[index].collapsed {
        // Store expanded size, shrink to header-only
        nodes[index].size = CGSize(width: nodes[index].size.width, height: 44)
    } else {
        // Recalculate from children
        recalculateFolderSizes()
    }
    scheduleDebouncedSave()
}
```

- [ ] **Step 3: Verify build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep "error:" | grep "CanvasViewModel" | head -5`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add Sources/Cider/ViewModels/CanvasViewModel.swift
git commit -m "feat: auto-calculate folder group sizes from children count"
```

---

### Task 6: Viewport Culling for Collapsed Folders

When a folder is collapsed, its children should be excluded from rendering. Currently all children render inside the LazyVGrid regardless of collapsed state. Ensure viewport culling properly accounts for collapsed parent nodes.

**Files:**
- Modify: `Sources/Cider/Views/Canvas/NativeCanvasView.swift`

- [ ] **Step 1: Filter out children of collapsed folders in canvasContent**

In the `canvasContent` method, the current filter is:
```swift
node.parentNodeID == nil && nodeIntersects(node, rect: cullRect)
```

This already works — children have `parentNodeID != nil` so they're excluded from top-level rendering. The `CanvasFolderGroupView` handles showing/hiding children via the `collapsed` flag. No code change needed here, but verify the behavior.

- [ ] **Step 2: Ensure collapsed folders have correct hit areas**

When collapsed, the folder's `node.size.height` should be 44 (header only). The viewport culling uses `node.size` for intersection testing, so collapsed folders will have a small footprint. Verify this works by checking the JSON after collapsing:

```bash
.build/arm64-apple-macosx/debug/cider-cli canvas collapse Gaming
.build/arm64-apple-macosx/debug/cider-cli canvas show --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
for n in d['nodes']:
    if n.get('nodeType')=='folderGroup' and 'Gaming' in str(n.get('metadata',{}).get('folderName','')):
        print(f'Size: {n[\"size\"]}')
        print(f'Collapsed: {n[\"metadata\"].get(\"collapsed\")}')
"
```

- [ ] **Step 3: Commit (if changes were needed)**

```bash
git commit -m "fix: viewport culling respects collapsed folder sizes"
```

---

### Task 7: Polish — Dot Grid Rendering Performance

The dot grid draws individual circles in a nested loop. At moderate zoom this can draw thousands of circles per frame. Batch them into a single Path for better GPU utilization.

**Files:**
- Modify: `Sources/Cider/Views/Canvas/NativeCanvasView.swift`

- [ ] **Step 1: Batch dot grid into a single Path**

Replace the individual `context.fill(Path(ellipseIn:))` calls with a single path:

```swift
@ViewBuilder
private func dotGrid(in size: CGSize) -> some View {
    Canvas { context, canvasSize in
        let baseSpacing: CGFloat = 20
        let spacing = baseSpacing * effectiveZoom
        guard spacing > 6, spacing < 200 else { return }

        let offsetX = effectivePan.x.truncatingRemainder(dividingBy: spacing)
        let offsetY = effectivePan.y.truncatingRemainder(dividingBy: spacing)

        let cols = Int(canvasSize.width / spacing) + 2
        let rows = Int(canvasSize.height / spacing) + 2
        let totalDots = cols * rows
        guard totalDots < 5000 else { return }

        let dotSize: CGFloat = max(1, 1.5 * effectiveZoom)
        var path = Path()

        for col in 0..<cols {
            for row in 0..<rows {
                let x = CGFloat(col) * spacing + offsetX
                let y = CGFloat(row) * spacing + offsetY
                path.addEllipse(in: CGRect(
                    x: x - dotSize / 2,
                    y: y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                ))
            }
        }

        context.fill(path, with: .color(Color.white.opacity(0.08)))
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | grep "error:" | grep "NativeCanvas" | head -5`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add Sources/Cider/Views/Canvas/NativeCanvasView.swift
git commit -m "perf: batch dot grid into single Path for GPU efficiency"
```

---

## Summary

| Task | Type | Impact | Risk |
|------|------|--------|------|
| 1. O(n) lookup fix | Performance | High — O(n^2) → O(1) for card rendering | Low |
| 2. Remove MagnifyGesture | Polish | Medium — cleaner zoom behavior | Low |
| 3. Folder collapse/expand | Feature | High — key Phase 2 feature | Medium |
| 4. CLI collapse/expand | Feature | Low — tooling for agents | Low |
| 5. Folder auto-sizing | Feature | Medium — correct folder containers | Low |
| 6. Culling + collapsed | Polish | Low — verify existing behavior | Low |
| 7. Dot grid batching | Performance | Medium — smoother grid rendering | Low |

Tasks 1-2 are independent quick wins. Tasks 3-6 form a dependency chain (3 → 4 → 5 → 6). Task 7 is independent.
