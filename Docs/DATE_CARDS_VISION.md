# Date Cards Vision

Date cards are calendar-linked items — events, reminders, deadlines, and recurring dates. They bridge the gap between a full calendar app and simple task management by treating dates as cards in your library.

---

## Storage

Date cards are stored as standard `.ics` files (iCalendar VEVENT, RFC 5545). See `Docs/PER_FILE_STORAGE.md` for the full spec.

---

## Event Lifecycle & Library Clutter

### Problem
One-off events like "Dentist" become dead weight after they pass. In a card-based library, past events clutter the feed and push active content down. Recurring events don't have this problem — they always have a next occurrence.

### Solution: Smart Visibility Rules

**Default library behavior:**
- Hide events that are **completed AND non-recurring** from the Home/library feed
- Overdue uncompleted events stay visible (they're actionable — user forgot or hasn't dealt with them)
- Recurring events always visible (next occurrence is relevant)

**Event-specific views:**
- A saved view filtered to date cards shows ALL events — past, completed, everything
- This is an intentional "show me my events" action, so no filtering

**Per-event auto-expiration (optional):**
- Individual events can opt into auto-trash: "Delete X days after event date"
- Perfect for throwaway events (dentist, package delivery, one-time reminders)
- User explicitly enables this per card — nothing disappears without consent

### Key Principle
Overdue events should NAG, not hide. Auto-completing past events would mask things the user forgot about. The user must manually mark an event complete to dismiss it from the feed.

---

## Calendar View (Future)

A calendar view built around the user's events, with "ghost cards" filling in days without items. Not a full-blown calendar app — just a date-oriented way to browse your cards.

- Events are shown in context of their date (past events aren't clutter here, they're historical)
- Overdue uncompleted events get prominent visual treatment (red badge, overdue indicator)
- Ghost cards on empty days keep the visual rhythm and invite the user to add events
- Ties into the existing `DateCard.urgency()` system for surfacing approaching dates

---

## Ideas / Backlog

- Drag `.ics` files into Cider to import events from other calendar apps
- Export/share events as `.ics` (already possible — just share the file from Finder)
- Calendar widget in the Home tab showing upcoming events
- Integration with system Calendar.app via EventKit (read-only sync)
