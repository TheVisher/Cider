# Todos And Reminders Architecture

## Local Scheduling

`DateCardNotificationService` reconciles macOS notification requests from current `DateCard` state. It uses deterministic identifiers based on card ID, occurrence, and reminder offset, and only removes stale date-card notifications.

## Reconciliation

`ReminderReconciler` runs on launch, wake, screen wake, time-zone changes, configuration changes, day rollover, and next due timers.

It coordinates:

- local date-card notification rescheduling
- reminder outbox processing
- Telegram reminder processing
- scheduled memory review processing

## Remote Delivery Bridges

`ReminderOutbox` writes due reminders to `.cider/outbox/` for agent-delivered messages. Telegram reminder delivery is currently a bridge delivery path.

These are not the durable reminder model. Cider-owned `TodoCard`, `DateCard`, and `SurfacingRule` data remain authoritative.

## Future Wake Jobs

`Docs/Architecture/AGENT_SERVICE.md` describes a future durable wake-job architecture for provider/iMessage delivery. Until that is implemented, treat it as target architecture, not current reminder storage truth.

