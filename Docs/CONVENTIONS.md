# Cider Conventions

Status: canonical core doc.

## Code

- Follow existing local patterns before creating new abstractions.
- Keep feature code close to its owning model, service, and view surface.
- Prefer explicit service APIs over ad hoc file or database access from views.
- Use `os.Logger`, not `print()`, for app runtime logging.
- Keep comments rare and useful.
- Preserve user data safety paths.
- Avoid high-risk force unwraps in sync, URL, and user-data paths.
- Keep large files on the radar; split when a file has multiple unrelated reasons to change.

## SwiftUI And AppKit

- Use SwiftUI for app surfaces and AppKit where macOS behavior requires it.
- Preserve non-activating panel behavior where expected.
- Use Cider design tokens for visual constants.
- Respect Reduce Motion for animations.
- Avoid direct `CiderConfig.load()` or heavy disk work from SwiftUI body rendering.
- Guard same-value ViewModel updates when they could trigger render loops.
- Be careful with AppKit popovers and DatePicker-like controls in non-activating panel contexts.
- Use compact GeometryReader/measurement patterns that do not expand layout unexpectedly.

## Storage And Data Safety

- Watchers should compare before writing to avoid self-triggered loops.
- Bookmark dedup/adoption should preserve stable identity and avoid folder-order flip-flops.
- Trash/restore must handle sidecars and duplicate-delete cases without direct file removal.
- URL rewrites and folder moves must persist, not only update in memory.
- Date-only values are calendar days, not UTC instants. Birthdays, all-day events, due dates without explicit times, and Kanban `created` dates should parse and render with local calendar semantics via `CiderLocalDate`; real appointments, logs, and timestamps remain instants displayed in the Mac's current timezone.

## Docs

- The active docs are the core docs in `Docs/INDEX.md`.
- Update an existing core doc before creating a new doc.
- Do not create docs for temporary implementation thinking.
- Completed plans/specs are harvested and deleted.
- Old docs are deleted after durable facts are moved into core docs or cards.

## Kanban

- Kanban owns active work, roadmap, QA evidence, bugs, implementation notes, and handoff context.
- Cards should be useful to a future agent.
- Prefer child cards over forever-cards when scope grows.
- Keep dates quoted in board YAML.

## Git

- Do not revert unrelated user changes.
- Keep commits scoped.
- Use git history as the archive for deleted docs.
