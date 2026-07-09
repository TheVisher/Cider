# Cider Design

Status: canonical core doc.

Cider should feel like a calm native memory cockpit: fast capture, clear review, useful resurfacing, and enough restraint that the user trusts it with real life context.

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
- Library should open to the complete visual collection and use subtle, low-weight multi-select pills for fast show/hide filtering. Keep item-type filters, workflow state, and Space/entity lenses conceptually distinct so the control row stays calm.
- Use one global search interaction and result vocabulary. The visible Library search field and `⌘K` are two entry points to the same search; `⌘K` may additionally expose quick actions without becoming a second search product.
- Review surfaces should make uncertainty visible and correction cheap.
- Detail views should reveal metadata without overwhelming the main content.
- Kanban should optimize for scanning and handoff.
- Dashboard should answer what matters now, why it matters, and what action is available.
- Spaces should feel like sibling command surfaces over the same memory system, not unrelated empty pages.
- Chat should show state clearly: idle, running, awaiting approval, failed, repaired.

## Layout Contracts

- Panel/sidebar padding should stay consistent across major surfaces.
- Cards should remain scannable and stable under hover, selection, and metadata changes.
- Tables/lists should keep predictable row heights and avoid text overlap.
- Compact overlays should be discoverable without permanently stealing space.
- Accessibility adaptations should preserve the task flow, not only pass contrast checks.

## Design Debt

Design audits and old visual reports should not remain as permanent docs. Turn unresolved work into Kanban cards, promote durable rules here, then delete the old report.
