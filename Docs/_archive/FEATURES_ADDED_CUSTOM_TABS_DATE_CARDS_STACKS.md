# Features Added: Custom Tabs, Date Cards, Stacks

Date: 2026-02-20
Branch: `feature/custom-tabs-date-cards-stacks`

## Saved Views and Tabs

1. Added persistent saved/custom view tabs.
2. Added saved view create flow from Home title bar.
3. Added saved view rename flow.
4. Added saved view delete flow.
5. Added saved view close/unpin behavior.
6. Added saved view naming logic using lowest available `View N`.

## Saved View Filters and Controls

1. Added entity-type filter chips:
   - Bookmarks
   - Notes
   - Date Cards
   - Contacts
2. Added saved-view text query search (`Search this view`).
3. Added saved-view sort menu:
   - Created (Newest/Oldest)
   - Updated (Newest/Oldest)
   - Title (A-Z/Z-A)
4. Added completed-items toggle filter.
5. Added label-based filter chips.
6. Added saved-view display mode chips:
   - List
   - Grid
   - Masonry

## Calendar Projection and Date Cards

1. Added calendar projection mode within saved views.
2. Added week/month projection toggle.
3. Added period navigation (previous/next/today).
4. Added ghost day cells (default on).
5. Added ghost cell toggle on/off.
6. Added create-date-card from ghost day click.
7. Added Date Card editor sheet (create/edit/delete).
8. Added Date Card label assignment and inline label creation.
9. Added Date Card `amount` field (optional).
10. Added Date Card amount rendering in list row and card view.
11. Added Date Card visual card component for grid/masonry layouts.

## Contact Cards

1. Added Contact Card model/storage integration.
2. Added Contact Card create/edit/delete sheet.
3. Added Contact Card visual card component.
4. Added Contact Card list row component.
5. Added Contact Card labels support.
6. Added Contact birthday field support.
7. Added birthday-driven date card creation/update from contact editor.

## Backlinks and Cross-Entity Navigation

1. Added bidirectional linking between Date Cards and Contacts.
2. Added context menu action to link Date Card -> Contact.
3. Added context menu action to link Contact -> Date Card.
4. Added linked-items context menu to open linked entities.
5. Added open handlers for linked:
   - Bookmark
   - Note
   - Date Card
   - Contact

## Stacks and Surfacing

1. Added Stack model/storage and manager sheet.
2. Added stack create/rename/delete.
3. Added stack templates:
   - Blank
   - Bills
   - Birthdays
   - Schedule
4. Added stack matching rules:
   - hasDate
   - isIncomplete
   - entityType
   - hasLabel
5. Added stack surfacing rules:
   - pinUntilDone
   - surfaceDaysBeforeDate
   - remindBeforeMinutes
6. Added configurable surfacing values (stepper controls for days/minutes).
7. Added stack sort modes:
   - attention
   - time
8. Added stack summary modes:
   - none
   - bills
9. Added surfaced stacks section in saved views.
10. Added stack card actions:
    - Open detail sheet
    - Toggle pinned
    - Open stack manager preselected
11. Added stack detail sheet item actions:
    - Mark done / undo
    - Snooze 1 day
    - Hide in current sheet session
12. Added bills summary panel in stack detail:
    - Total
    - Paid
    - Remaining
    - Completed count
13. Added manual stack membership management in stack manager.
14. Added right-click quick action `Add to Stack` from saved-view items.

## Reliability and Behavior Improvements

1. Added stack detail selection by stack ID instead of stale object only.
2. Added stack detail snapshot fallback when surfacing changes mid-session.
3. Added saved-view empty-state behavior that keeps controls available.

## Data, Projection, and Persistence Foundation

1. Added library projection model supporting:
   - Bookmarks
   - Notes
   - Date Cards
   - Contacts
2. Added `LibraryViewModel` to unify filtering/sorting/surfacing.
3. Added persistence stores for:
   - Date Cards
   - Contacts
   - Labels
   - Stacks
   - Saved Views
4. Added shared JSON storage path utility for new stores.

## Compatibility and Scope Notes

1. Bookmarks and Notes fixed tabs were kept for compatibility (not removed).
2. Visual polish for date cards/ghost cells/stacks remains intentionally deferred.

## Tests Added

1. Added codable round-trip tests for temporal models:
   - DateCard codable round-trip
   - SavedView codable round-trip

