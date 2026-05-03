# Todos And Reminders

**Status:** Active / partially implemented  
**Owner surface:** Cider Desktop first; Dashboard, Telegram/text, and future mobile as surfacing channels  
**Source of truth:** This feature folder is the durable source of truth for Cider todos, date-card reminders, and resurfacing behavior.

## What This Feature Does

Todos and reminders are Cider's action and resurfacing layer.

- Todos track actionable tasks, checklist items, due dates, priority, completion, labels, folders, links, and notes.
- Date cards track events, reminders, deadlines, recurring dates, location, amount, completion, labels, folders, links, and surfacing rules.
- Reminder delivery is local-first. Cider stores structured reminder data and deterministic services deliver notifications or bridge messages.
- The assistant may help create or update reminders, but the assistant is not the scheduler of record.

## Source-Of-Truth Rules

- `TodoCard` is the source of truth for todo/task records.
- `DateCard` plus `SurfacingRule.remindBeforeMinutes` is the source of truth for time/date reminders.
- `ReminderReconciler` coordinates notification and remote-delivery reconciliation.
- `DateCardNotificationService` owns local macOS notification scheduling.
- `ReminderOutbox` and Telegram reminder handling are bridge delivery paths, not the durable reminder model.
- Apple Reminders may be used as a temporary fallback for unsupported requests such as location-aware reminders, but it is not the long-term Cider source of truth.

## Related Docs

- `Docs/Features/TodosReminders/PRODUCT.md`
- `Docs/Features/TodosReminders/DATA_MODEL.md`
- `Docs/Features/TodosReminders/ARCHITECTURE.md`
- `Docs/Features/TodosReminders/CLI.md`
- `Docs/Features/TodosReminders/TESTING.md`
- `Docs/Features/TodosReminders/ROADMAP.md`
- `Docs/Features/TodosReminders/DECISIONS.md`
- `Docs/Product/CIDER_LIFE_ASSISTANT_VISION.md`
- `Docs/Product/CIDER_ADAPTIVE_ROADMAP.md`
- `Docs/Architecture/AGENT_SERVICE.md`

