# Cider Update Reminder Design

Date: 2026-04-26
Status: Proposed

## Goal

Make available Sparkle updates visible inside Cider without forcing users to stare at a permanent nag. The reminder should be clear enough to discover, subtle enough to live in the sidebar, and fully hideable by the user.

## User Experience

When Sparkle knows an update is available and sidebar reminders are enabled:

- In the expanded sidebar profile/footer section, show an `Update Available` quick action row above `Settings`.
- In the collapsed sidebar footer, show a small accent badge on the compact profile/footer affordance so users can still notice the update.
- The reminder may pulse briefly when it first appears, then settle into a static indicator.
- The pulse must be disabled when Reduce Motion is enabled.
- Selecting the update row or badge should call the existing Sparkle update flow through `SparkleUpdaterService.shared.checkForUpdates()`.

The expanded row should include a quiet dismiss affordance. Dismissing hides the sidebar reminder for the currently available update version/build, but a later update version may show the reminder again.

## Settings

Add a toggle under `Settings > General > Startup > Updates`, below `Check for updates automatically` and above `Check for Updates Now`:

- Title: `Show update reminders in sidebar`
- Subtitle: `Show a sidebar badge when a new version of Cider is available`
- Default: on

Turning this off hides the expanded row and collapsed badge. It does not change Sparkle automatic update checks.

## State Model

Extend the updater service with observable state for the UI:

- whether an update is currently available
- the available update version/build identifier when known
- whether sidebar reminders are enabled
- the dismissed update identifier, persisted in user defaults

The sidebar should show a reminder only when:

- an update is available
- sidebar reminders are enabled
- the available update identifier is not the dismissed identifier

If Sparkle reports no update or finishes an update session without an available update, the update-available UI state should clear.

## Integration

`SparkleUpdaterService` already owns Sparkle and is shared by Settings. It should become the source of truth for update reminder UI state, since both Settings and the sidebar need to observe the same updater status.

The existing Sparkle modal/window ordering behavior remains unchanged. The reminder only changes how users discover the existing update flow.

## Components

Update these surfaces:

- `SparkleUpdaterService`: publish update availability, reminder preference, dismissal, and update action.
- `CiderPanelView+SidebarFooter`: render the expanded update row and collapsed badge.
- `SettingsView+SubcategoryContent`: add the new sidebar reminder toggle under Updates.

The sidebar should keep using existing quick-action button styles where possible. Any badge or pulse view should be small and local to the sidebar footer file unless reuse becomes necessary.

## Error Handling

If Sparkle cannot check for updates, the reminder action should quietly do nothing through the existing `canCheckForUpdates` guard.

If the available update lacks a usable display/build identifier, use a stable fallback derived from Sparkle metadata. The dismissal key must be stable for one available update and different for a later update.

## Testing

Add focused unit tests for reminder visibility logic:

- visible when update is available, reminders are enabled, and update has not been dismissed
- hidden when reminders are disabled
- hidden after dismissing the current update
- visible again for a different update identifier

Manual verification should cover:

- expanded sidebar update row appears and triggers Sparkle check
- collapsed sidebar badge appears
- Settings toggle hides both sidebar surfaces
- dismissal hides the current update reminder
- Reduce Motion disables pulsing
