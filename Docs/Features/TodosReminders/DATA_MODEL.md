# Todos And Reminders Data Model

## TodoCard

Implemented in `Sources/Cider/Models/TodoCard.swift`.

Key fields:

- `id`
- `title`
- `details`
- `checklist`
- `dueDate`
- `priority`
- `isCompleted`
- `completedAt`
- `labelIDs`
- `notes`
- `linkedEntities`
- `folderID`
- `rules`
- `createdAt`
- `updatedAt`

## TodoChecklistItem

Checklist items may carry their own title, completion state, sort order, due date, amount, URL, and subtasks.

## DateCard

Implemented in `Sources/Cider/Models/DateCard.swift`.

Key fields:

- `id`
- `title`
- `details`
- `startAt`
- `endAt`
- `allDay`
- `location`
- `amount`
- `recurrenceRule`
- `isCompleted`
- `completedAt`
- `labelIDs`
- `linkedEntities`
- `folderID`
- `rules`
- `createdAt`
- `updatedAt`

## SurfacingRule

Implemented in `Sources/Cider/Models/SurfacingRule.swift`.

Rule types:

- `pinUntilDone`
- `surfaceDaysBeforeDate`
- `remindBeforeMinutes`

For v1 reminders, `DateCard.rules` with `remindBeforeMinutes` is the Cider-owned trigger model.

