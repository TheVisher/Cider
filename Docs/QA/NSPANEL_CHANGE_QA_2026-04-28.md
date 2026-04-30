# NSPanelChange QA Notes

Date: 2026-04-28
Branch: `codex/NSPanelChange`

## Scope

Cider is moving from "the whole app is an `NSPanel`" to a regular main app window with floatable `NSPanel` surfaces. This pass checked the live Debug app after building `CiderApp`.

## Verified

- Launch opened the main Cider surface as an accessibility `AXStandardWindow`, not a panel/dialog.
- Main window resized horizontally and vertically from the bottom-right custom resize affordance.
- Dashboard layout adapted after resize without clipping under the sidebar or off the right edge.
- Library masonry rendered inside the viewport after shrink and tab switching.
- Library grid and list modes switched from the view options popover and stayed inside the content bounds.
- Inbox masonry rendered after resizing and switching from Dashboard and Library.
- The `Surfaces > Show Drop Zone` path opened the Drop Zone as a floating panel surface.
- Focus returned to the normal main window without converting it into a panel-like app surface.

## Notes

- The focused masonry regression test suite passed with 9 tests.
- Live QA did not reproduce the earlier masonry width feedback issue.
- The Card Size slider was visible in the view options popover; the coordinate-driven test did not reliably move the slider thumb, so this should get a manual follow-up pass.
- Coordinate-driven dragging of custom title/sidebar drag zones was inconclusive. Native manual QA should confirm drag zones with a real pointer before this branch is considered fully polished.
- Detail-surface float button clicks were also inconclusive through the automation layer. Drop Zone verified the floating-panel manager path, but note/bookmark/contact/todo pop-out should still get a manual pointer pass.
