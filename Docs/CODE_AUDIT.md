# Cider Code Audit

Automated read-only audit for animation, color, font, and spacing token violations.
Runs every 15 minutes through: Views/Bookmarks → Views/Notes → Views/Home → Views/Shared → Views/Search → Views/Settings → ViewModels → Services.

---

## Views/Bookmarks — 2026-03-17

**BookmarkCard.swift**
- Line 80, 89: `.white` hardcoded instead of `CiderColors.*`
- Line 99: `.black` hardcoded in LinearGradient instead of `CiderColors.*`

**BookmarkThumbnailView.swift**
- Line 64, 98: `.system(size: 9, ...)` hardcoded font size instead of `CiderFont.*`
- Line 70, 104, 312, 321–322: `Color.black.opacity(...)` hardcoded instead of `CiderColors.*`
- Line 305: Hardcoded frame dimensions `5, 5` instead of spacing token
- Line 340: `withAnimation(.snappy)` — no `reduceMotion` check
- Line 346: `.system(size: 10, weight: .bold)` hardcoded font size

**BookmarkDetailsDraft.swift**
- Line 58: Hardcoded spacing value `2` (use `Spacing.xxs`)
- Line 428, 605: `.system(size: 8 * CiderFont.scale, ...)` — partially tokenized but raw size 8 should be a named CiderFont style
- Line 596: Hardcoded frame size `44, 22`
- Line 976: `.system(size: 14, weight: .bold)` hardcoded font size
- Line 1020: `.system(size: 8, weight: .bold)` hardcoded font size

---

## Views/Notes — 2026-03-17

**InlineNoteEditorView.swift**
- Line 147–150: `.system(size: 13, ...)` hardcoded font sizes (×4) instead of `CiderFont.*`
- Line 198: Hardcoded frame width `248`
- Line 218, 233, 283, 312: Hardcoded frame dimensions `28, 28`
- Line 231, 276, 310, 359, 488: `.system(size: 12, ...)` hardcoded font sizes instead of `CiderFont.*`
- Line 268: Hardcoded frame dimensions `10, 10`
- Line 278: `cornerRadius: 1` — use `Radius.xs` (4) instead
- Line 280: Hardcoded frame `14 × 3`
- Line 328, 353, 1121: `.system(size: 10, ...)` hardcoded font sizes instead of `CiderFont.*`
- Line 475: Hardcoded frame width `200`
- Line 812, 1178: `.system(size: 11, ...)` hardcoded font sizes instead of `CiderFont.*`
- Line 838: Hardcoded frame width `260`

**NoteListRow.swift** ✅ No violations found.
**TipTapEditorView.swift** ✅ No violations found.
**NoteCardView.swift** ✅ No violations found.

---

## Views/Home — 2026-03-17

- `ContinueSectionView.swift:112` — `withAnimation(.snappy)` missing `reduceMotion` check
- `HomeDashboardView.swift:228` — Hardcoded `220` instead of `LibraryCardSizing.cardMinWidth`

---

## Views/Shared — 2026-03-17
- `SelectionCheckmark.swift:10` — Uses `.system(size: 10, weight: .bold)` instead of CiderFont token

---

## Views/Search — 2026-03-17

**SearchTabContent.swift**
- `SearchTabContent.swift:136` — Hardcoded `spacing: 1` instead of spacing token

**SearchPaletteView.swift**
- `SearchPaletteView.swift:225` — `Color.black` hardcoded instead of `CiderColors.*`
- `SearchPaletteView.swift:226` — Hardcoded `blur(radius: 24)`
- `SearchPaletteView.swift:227` — Hardcoded `offset(y: 12)` instead of spacing token
- `SearchPaletteView.swift:228` — Hardcoded `.opacity(0.7)`
- `SearchPaletteView.swift:230` — Hardcoded `proxy.size.height * 0.22` magic multiplier
- `SearchPaletteView.swift:813` — Hardcoded `spacing: 1` instead of spacing token

---

## Views/Settings — 2026-03-17

- `StorageSettingsView.swift:62` — `.system(size: 28)` hardcoded font size instead of CiderFont token
- `SettingsComponents.swift:30` — `Color.black.opacity(0.5)` hardcoded color instead of CiderColors.*
- `SettingsComponents.swift:35` — `Color(nsColor: NSColor.windowBackgroundColor)` hardcoded system color
- `SettingsComponents.swift:307, 311` — `.foregroundColor(.orange)` hardcoded color (×2) instead of CiderColors.*
- `SettingsComponents.swift:308, 315, 322` — `.system(size: 12)` hardcoded font size (×3) instead of CiderFont.*
- `SettingsComponents.swift:314` — `.foregroundColor(.green)` hardcoded color instead of CiderColors.*
- `SettingsComponents.swift:483` — `.system(size: previewSize, weight: .medium)` hardcoded font instead of CiderFont.*
- `SettingsComponents.swift:702` — `.system(size: 11, weight: .medium, design: .monospaced)` hardcoded font instead of CiderFont.*
- `SettingsView.swift:105` — `Color.black.opacity(0.55)` hardcoded color instead of CiderColors.*
- `SettingsView.swift:139` — `Color.black.opacity(0.4)` hardcoded color instead of CiderColors.*
- `SyncSettingsView.swift:21, 25` — `.foregroundColor(.orange)` hardcoded color (×2) instead of CiderColors.*
- `SyncSettingsView.swift:22, 29, 36` — `.system(size: 12)` hardcoded font size (×3) instead of CiderFont.*
- `SyncSettingsView.swift:28` — `.foregroundColor(.green)` hardcoded color instead of CiderColors.*

---

## ViewModels — 2026-03-17
✅ No violations found.

---

## Services — 2026-03-17

**ScreenCaptureService.swift** (AppKit/CoreGraphics drawing code)
- `ScreenCaptureService.swift:176` — `NSColor.black.withAlphaComponent(0.35)` hardcoded instead of CiderColors.*
- `ScreenCaptureService.swift:195` — `NSColor.white.withAlphaComponent(0.9)` hardcoded instead of CiderColors.*
- `ScreenCaptureService.swift:197` — Magic number `insetBy(dx: -0.75, dy: -0.75)` for stroke inset
- `ScreenCaptureService.swift:200` — Hardcoded corner handle size `h: 6`
- `ScreenCaptureService.swift:205` — `NSColor.white.cgColor` hardcoded instead of CiderColors.*
- `ScreenCaptureService.swift:212` — `.system(size: 11)` hardcoded font size instead of CiderFont.*
- `ScreenCaptureService.swift:213, 221` — `NSColor.white` / `NSColor.black.withAlphaComponent(0.55)` hardcoded instead of CiderColors.*

All other 59 service files ✅ No violations found.

---

## Audit Complete — 2026-03-17

**Total violations by category:**
| Category | Count |
|----------|-------|
| Animation type (easeIn/easeOut/linear) | 0 |
| Missing reduceMotion check | 2 |
| Hardcoded color | ~25 |
| Hardcoded font size | ~20 |
| Magic number / spacing | ~15 |

**Top files to fix (most violations):**
1. `InlineNoteEditorView.swift` — ~25 violations (font sizes, frame dimensions)
2. `SettingsComponents.swift` — ~8 violations (colors, fonts)
3. `BookmarkDetailsDraft.swift` — ~6 violations (colors, font sizes)
4. `BookmarkThumbnailView.swift` — ~6 violations (colors, font sizes)
5. `SyncSettingsView.swift` — ~5 violations (colors, fonts)

**Healthiest areas:** ViewModels (clean), Views/Shared (1 violation across 27 files), Views/Home (2 violations).
**Needs most attention:** Views/Notes (InlineNoteEditorView), Views/Settings.

**SearchPaletteView.swift**
- Line 225: `Color.black` hardcoded instead of `CiderColors.*`
- Line 226: Hardcoded `blur(radius: 24)` — magic number for blur radius
- Line 227: Hardcoded `offset(y: 12)` — use spacing token instead
- Line 228: Hardcoded `opacity(0.7)` — magic number opacity
- Line 230: Hardcoded `proxy.size.height * 0.22` — magic number multiplier for padding
- Line 245: Hardcoded `opacity(0)` for hidden button workaround — magic number
- Line 813: Hardcoded `spacing: 1` — use `Spacing.xxs` (2) instead
