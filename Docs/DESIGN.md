# Cider Design

Status: canonical core doc.

Cider should feel like a focused Mac utility: fast, calm, tactile, and useful.

## Visual Principles

- Use Cider color, spacing, radius, font, and animation tokens.
- Avoid hardcoded styling values in feature UI.
- Prefer quiet density over oversized marketing-style layouts.
- Keep controls predictable and native-feeling.
- Use acrylic/visual-effect materials where the app's design system expects them. Prefer the established AppKit visual-effect stack and do not adopt unrelated glass APIs casually.
- Keep cards and panels readable under dark mode.
- Provide Reduce Transparency fallbacks for material-heavy surfaces.
- Use inset strokes/borders where outside strokes create layout or clipping artifacts.

## Interaction Principles

- Do not steal focus.
- Respect Reduce Motion.
- Use spring animations for motion unless motion is disabled.
- Keep hit targets stable and avoid layout shift.
- Make drop targets visible when drag/drop is supported.
- Prefer undo/trash over surprise destructive actions.
- Content must accept the proposed width from its container; avoid layout that measures itself into stale or impossible sizes.
- Thumbnails should scale from actual card width and aspect ratio.
- Use `.fit` and `.fill` intentionally; do not crop inspectable content by accident.

## Feature Surfaces

- Capture flows should be fast and forgiving.
- Detail views should reveal metadata without overwhelming the main content.
- Kanban should optimize for scanning and handoff.
- Dashboard should answer why something matters to the user.
- Chat should show state clearly: idle, running, awaiting approval, failed, repaired.

## Layout Contracts

- Panel/sidebar padding should stay consistent across major surfaces.
- Cards should remain scannable and stable under hover, selection, and metadata changes.
- Tables/lists should keep predictable row heights and avoid text overlap.
- Compact overlays should be discoverable without permanently stealing space.
- Accessibility adaptations should preserve the task flow, not only pass contrast checks.

## Design Debt

Design audits and old visual reports should not remain as permanent docs. Turn unresolved work into Kanban cards, promote durable rules here, then delete the old report.
