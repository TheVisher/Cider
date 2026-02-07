# Cider Release Checklist

## Build + Packaging
- [ ] Create Xcode project or ensure SPM builds a proper app bundle.
- [ ] Info.plist: LSUIElement / activation policy, app name, versioning.
- [ ] Entitlements: Accessibility, Automation, Screen Recording (if used).
- [ ] Code signing configured for local dev.
- [ ] Notarization pipeline defined (later).

## Permissions + Privacy
- [ ] Accessibility prompt shown once, with clear instructions.
- [ ] Screen Recording: only request when user enables window previews.
- [ ] Reduce Transparency / Reduce Motion respected.

## UI/UX Compliance (Acrylic Style)
- [ ] Acrylic background: NSVisualEffectView with dark overlays.
- [ ] Custom shadows drawn as blurred shapes (not .shadow() modifier).
- [ ] Borders use .stroke() with inset, not .strokeBorder().
- [ ] All spacing uses design tokens (no magic numbers).
- [ ] All animations use spring presets.
- [ ] Context menus are native NSMenu.

## Command Palette QA
- [ ] Palette never steals focus.
- [ ] Double-tap activation works reliably.
- [ ] Single-tap activation works reliably (if configured).
- [ ] Opens on screen where mouse is located.
- [ ] Search field auto-focuses and filters windows/apps in real-time.
- [ ] Pinned apps show running indicators.
- [ ] Pinned apps drag-to-reorder works.
- [ ] App folders create, expand, collapse correctly.
- [ ] Window actions work (focus, close, minimize).
- [ ] Move to monitor works.
- [ ] Drag windows between monitors works.
- [ ] Keyboard navigation (↑↓ navigate, Enter focus, Esc dismiss).
- [ ] Settings persist across launches.

## Option+Tab Window Cycling QA
- [ ] Hold Option + Tab cycles through windows.
- [ ] Release Option focuses selected window.
- [ ] Overlay shows on correct screen.
- [ ] Respects "cycle all screens" setting.

## Settings Window QA
- [ ] Opens on same screen as palette.
- [ ] All tabs function correctly.
- [ ] Text size changes apply immediately.
- [ ] Palette size changes apply after reopening palette.

## Platform QA
- [ ] Works on primary display.
- [ ] Works on secondary displays.
- [ ] Multiple Spaces behavior.
- [ ] Fullscreen apps (palette should appear above).
- [ ] Stage Manager on/off compatibility.
- [ ] Different accent colors.
- [ ] Light and dark mode.

## Accessibility QA
- [ ] Reduce Motion: 0.2s opacity crossfades, no scale animations.
- [ ] Reduce Transparency: opaque backgrounds.
- [ ] VoiceOver labels on all buttons.
- [ ] Keyboard navigation functional.

## Performance
- [ ] Window polling interval tuned (1 second).
- [ ] CPU usage stable when palette is hidden.
- [ ] No UI jank during hover/scroll.
- [ ] Memory usage stable over time.

## Marketing Readiness
- [ ] 15-30s teaser video recorded.
- [ ] Key screenshots exported.
- [ ] README + quick start guide.
