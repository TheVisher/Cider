# TipTap Editor Architecture

> The notes editor uses a TipTap/ProseMirror instance inside a WKWebView. Read this before modifying the editor, note content serialization, or external file handling.

---

## Core Architecture

- **Singleton WebView** — `NotesViewModel` owns the WKWebView (created via `ensureEditorWebView()`). `TipTapEditorView` is a thin NSView container that borrows it. Only one surface displays the editor at a time; the WebView moves between containers.
- **Coordinator** — `TipTapEditorCoordinator` handles JS-to-Swift message routing. Owned by the ViewModel, not by SwiftUI.
- **Editor resources** — `Resources/TipTapEditor/editor.html` + `editor.css` + `editor.js` (minified bundle)
- **Build** — `npm run build` in `tiptap-editor/` uses esbuild, copies minified bundle to `Sources/Cider/Resources/TipTapEditor/`

---

## CSS Gotchas

- **Code block line-height:** `line-height` on `<pre>` (block) controls code block spacing, NOT on `<code>` (inline child). The `<pre>` inherits body's `line-height` if not explicitly set.
- **Table sizing:** `width:auto; table-layout:auto` for content-sized tables (not `width:100%` which stretches to fill)

---

## WebView Configuration

- **Access scope:** `allowingReadAccessTo` is set to `NSHomeDirectory()` — the editor can load images from any path under the user's home directory (notes, attachments, dragged images).
- **Navigation policy:** Deny-by-default: only `file://` and `about:` are allowed; all other schemes are blocked regardless of how the navigation was triggered. User-clicked external links are opened in the system browser then cancelled.
- **Panel drag exclusion:** `isInDraggableArea()` in `CiderPanel.swift` checks `if v is WKWebView { return false }` — without this, dragging inside the editor moves the entire panel.

---

## Image Serialization

- **Always use `<img>` HTML, never `![]()` markdown.** `CiderImage.serialize` uses `<img src="..." alt="..." />`. Reason: `![]()` inside a `<p style="text-align: ...">` block is treated as raw literal text by markdown-it (CommonMark type-6 HTML block rule). `<img>` is safe in both aligned and plain paragraphs.
- **CommonMark HTML block rule:** `<p>...</p>` (and other block-level HTML tags) are CommonMark type-6 HTML blocks — markdown-it does NOT parse markdown syntax inside them. So `<p style="text-align: center">![alt](src)</p>` renders the `![]()` as raw text, not an image.
- **Legacy migration:** `normalizeIncomingMarkdown` calls `convertMarkdownImagesInHtmlParagraphs` (in `editor.js`) to convert any `<p>..![]()</p>` patterns to `<p>..<img /></p>` on load.

---

## Content Sync & Save

- **Normalization round-trip:** Pushing raw markdown via `pushContentToEditor` fires `contentChanged` with TipTap-serialized output that may differ from the input even with zero edits. When loading external files, set a flag (`isLoadingExternalFile`) and absorb the first `contentChanged` by updating `lastSyncedDiskContent` to the normalized value without writing to disk.
- **`syncExternalContentFromEditor` vs external files:** The async JS eval safety net exists to catch final keystrokes for native notes. For external files it causes spurious writes — the async eval path may serialize differently than `contentChanged`, bypassing equality guards. Use `editingContent` as authoritative for external files; do not call `syncExternalContentFromEditor` from `flushSave`.
- **External file mtime integrity:** Every save path (`contentChanged` debounce, `flushSave`, any async sync) must guard with `content != lastSyncedDiskContent` before writing. Opening and closing a file with no edits must never touch the filesystem.

---

## ProseMirror Parse Issues

- **Text-align lost on image paragraphs:** ProseMirror's DOMParser empirically fails to read `textAlign` from `<p style="text-align: center">` when the paragraph contains `<img>` with NodeViews. markdown-it preserves the HTML correctly — the loss happens during ProseMirror parse. Fix: `repairTextAlignAfterParse()` in `editor.js` — parses input HTML into DOM, walks ProseMirror doc in parallel, applies missing `textAlign` via `tr.setNodeMarkup()` with `addToHistory: false`. Do NOT set `preventUpdate` on the repair transaction — `contentChanged` must fire so `editingContent` gets the corrected content for save.

---

## Debugging

- **JS-to-Swift debugging:** WKWebView `console.log` does NOT appear in Xcode debug console. Use `postEditorDiagnostic(message)` which calls `window.webkit.messageHandlers.editorDiagnostic.postMessage()` — coordinator routes to `NSLog`. Remove all diagnostic calls before shipping.
