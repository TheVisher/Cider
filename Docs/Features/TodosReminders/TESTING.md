# Todos And Reminders Testing

## Focused Tests

Relevant tests include:

- `DailyVaultReminderServiceTests`
- todo checklist tests
- event/date-card storage tests
- reminder notification/reconciler tests when present

Search current coverage with:

```bash
rg -n "Todo|Reminder|DateCard|Event" Tests/CiderTests
```

Run focused tests with:

```bash
swift test --filter DailyVaultReminderServiceTests
swift test --filter Todo
swift test --filter Reminder
swift test --filter DateCard
```

## Manual QA

- Create a todo with due date and priority.
- Complete and reopen the todo; verify completion persists.
- Add checklist items and toggle them.
- Create a date card with a reminder rule.
- Relaunch Cider and verify notification reconciliation does not duplicate notifications.
- Verify overdue/today/approaching date cards surface correctly.
- Verify Telegram/text reminder bridges do not become the durable source of truth.

