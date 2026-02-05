# Cider Roadmap

This roadmap is optimized for a **native macOS command palette experience**. It prioritizes stability, instant response, and strong first impressions over feature breadth.

## Product Principles
- **Native first**: semantic colors, system typography, acrylic materials.
- **Non-activating**: palette never steals focus.
- **Instant response**: palette appears within 100ms.
- **Minimal features, perfect behavior** per release.

---

## v0.1 — Core Command Palette (MVP) ✅

**Goal:** A stable, native-feeling command palette that solves daily window navigation.

**Deliverables**
- Command palette shell (NSPanel, borderless, non-activating).
- Acrylic background using NSVisualEffectView.
- Pinned apps: horizontal row with running indicators.
- Window list: grouped by app in palette; monitor grouping in legacy sidebar.
- Double-tap Option activation.
- Settings window with tabbed navigation.
- Multi-monitor support.
- Accessibility permission flow.

**Exit Criteria**
- ✅ No focus stealing.
- ✅ Window actions work across major apps.
- ✅ Settings persist across launches.
- ✅ Visuals match acrylic design system.

---

## v0.2 — Polish + Window Previews

**Goal:** Add visual polish and window thumbnails.

**Deliverables**
- Window preview thumbnails (requires Screen Recording permission).
- Drag to reorder pinned apps.
- Keyboard navigation (↑↓ to select, Enter to focus).
- App folders in pinned apps row.
- Search filtering of windows.

**Exit Criteria**
- Previews load quickly without blocking UI.
- Keyboard-only navigation is fully functional.
- App folders expand/collapse smoothly.

---

## v0.3 — Window Tiling + Organization

**Goal:** Advanced window management features.

**Deliverables**
- Window tiling (left half, right half, quadrants).
- Drag windows between monitors.
- Window grouping (manual groups).
- Split-screen shortcuts.

**Exit Criteria**
- Tiling works reliably on multi-monitor setups.
- Groups persist across app restarts.

---

## v0.4 — Companion Features

**Goal:** Add productivity features beyond window management.

**Deliverables**
- Quick capture notes (floating note window).
- Clipboard history (optional).
- Timer overlay for games/cooking.

**Exit Criteria**
- Companion windows float above fullscreen apps.
- Notes persist locally.
- Clipboard respects privacy settings.

---

## v1.0 — Public Release

**Goal:** Ship a stable, beautiful command palette replacement.

**Deliverables**
- Polished onboarding flow.
- App icon + brand assets.
- Packaging, signing, notarization.
- Documentation + quick start guide.
- Marketing website.

**Exit Criteria**
- App Store ready.
- No known crashes in 1 hour of use.
- All accessibility settings respected.

---

## Risks / Dependencies
- Accessibility API stability and user permissions.
- Screen Recording permission adoption rate.
- Multi-monitor edge cases (Spaces, full screen).
- Performance with frequent window list refresh.
