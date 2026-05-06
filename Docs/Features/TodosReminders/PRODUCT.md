# Todos And Reminders Product

## Product Promise

Cider should help Erik remember and act on things at the right time without turning memory management into homework.

## Current Behavior

- Todos are first-class library cards.
- Date cards represent events, reminders, deadlines, and recurring dates.
- Due/approaching todos and date cards appear in Home/Dashboard surfaces.
- Local notifications can fire for date cards with reminder rules.
- Agent/Telegram reminders are bridge surfaces over Cider-owned data.

## Product Principles

- Cider owns the structured reminder/task data.
- External systems are fallbacks or delivery channels.
- Overdue work should nag, not disappear.
- Recurring date cards should not be killed by completing one occurrence.
- Reminder creation/update must be safe, inspectable, and reversible.
- Dashboard and text briefings should be views over the same life context.
- Todos and events may need direct action URLs, such as payment portals, appointment links, forms, or check-in pages. A direct URL is an action affordance on the item, not necessarily a bookmark/library item.

## Non-Goals

- Do not make Apple Reminders the long-term source of truth.
- Do not treat Telegram delivery as the durable reminder model.
- Do not claim native geofence reminders are complete until Cider owns location-aware triggers.

