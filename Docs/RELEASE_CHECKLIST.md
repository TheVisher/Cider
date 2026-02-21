# Cider Release Checklist

## Build + Packaging
- [ ] Create Xcode project or ensure SPM builds a proper app bundle.
- [ ] Info.plist: LSUIElement / activation policy, app name, versioning.
- [ ] Entitlements: Accessibility, Automation.
- [ ] Code signing configured for local dev.
- [ ] Notarization pipeline defined (later).

## Permissions + Privacy
- [ ] Accessibility prompt shown once, with clear instructions.
- [ ] Reduce Transparency / Reduce Motion respected.

## UI/UX Compliance (Acrylic Style)
- [ ] Acrylic background: NSVisualEffectView with dark overlays.
- [ ] Custom shadows drawn as blurred shapes (not .shadow() modifier).
- [ ] Borders use .stroke() with inset, not .strokeBorder().
- [ ] All spacing uses design tokens (no magic numbers).
- [ ] All animations use spring presets.
- [ ] Context menus are native NSMenu.

## Floating Panel QA
- [ ] Panel never steals focus from active app.
- [ ] Double-tap Option activation works reliably.
- [ ] Opens on screen where mouse is located.
- [ ] Panel resizable from all edges.
- [ ] Sidebar auto-hides at compact width.
- [ ] Panel remembers position per-screen.
- [ ] Escape key or click outside dismisses panel.
- [ ] Settings persist across launches.

## Title Bar QA
- [ ] Tab bar shows Home tab (only fixed tab). Saved view tabs, search tabs, and external source tabs appear as created.
- [ ] Sidebar toggle button works.
- [ ] View options dropdown (bookmarks tab) — slider + view mode icons.
- [ ] Capture button (bookmarks tab) — captures active browser tab.
- [ ] Title bar drag-to-move works.

## Bookmarks QA
- [ ] Grid, List, Masonry views all render correctly.
- [ ] Card size slider updates card sizes fluidly.
- [ ] Masonry thumbnails show full images (no cropping, no padding).
- [ ] Grid thumbnails scale proportionally with card width.
- [ ] Cards resize as unified units (thumbnail + card shrink/grow together).
- [ ] Panel can shrink to minimum width even with large card sizes.
- [ ] Drag-and-drop URL to add bookmark works.
- [ ] Folder sidebar: create, select, assign bookmarks.
- [ ] Bookmark detail modal opens correctly.
- [ ] Bookmark enrichment (metadata fetch) works.
- [ ] Thumbnail drag-and-drop assignment works.

## Notes Editor QA
- [ ] Run `Docs/NOTES_EDITOR_SMOKE_CHECKLIST.md` end-to-end.
- [ ] Notes appear in folder sidebar.
- [ ] Note panel opens correctly.

## Settings QA
- [ ] Opens correctly from panel.
- [ ] All settings function correctly.
- [ ] Text size changes apply immediately.
- [ ] Default card size / view mode settings sync with panel.

## Platform QA
- [ ] Works on primary display.
- [ ] Works on secondary displays.
- [ ] Multiple Spaces behavior.
- [ ] Fullscreen apps (panel should appear above).
- [ ] Stage Manager on/off compatibility.
- [ ] Different accent colors.
- [ ] Light and dark mode.

## Accessibility QA
- [ ] Reduce Motion: no spring animations, opacity crossfades only.
- [ ] Reduce Transparency: opaque backgrounds.
- [ ] VoiceOver labels on all buttons.
- [ ] Keyboard navigation functional.

## Performance
- [ ] CPU usage stable when panel is hidden.
- [ ] No UI jank during hover/scroll.
- [ ] Memory usage stable over time.
- [ ] Masonry layout caching works (no redundant recomputation).
- [ ] View mode switching is near-instant.

## Marketing Readiness
- [ ] 15-30s teaser video recorded.
- [ ] Key screenshots exported.
- [ ] README + quick start guide.
