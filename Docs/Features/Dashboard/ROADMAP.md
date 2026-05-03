# Dashboard Roadmap

**Status:** Feature-specific roadmap.

---

## Current MVP

- Desktop/vault is source of truth.
- Persist one dashboard snapshot JSON under `.cider/dashboard/`.
- Keep existing overview dashboard as `Main`.
- Add topic tabs and card boards.
- Support seen/dismiss/rating/more-like-this/less-like-this/open-source actions.
- Keep Web/schema sync gated.

---

## Next Best Steps

1. Verify Dashboard CLI commands against the current main checkout.
2. Add or confirm seed data path for manual testing without fake live news.
3. Review Desktop UI in-app and capture screenshots once screenshot tooling works.
4. Add dashboard cards from report-only Cider project/doc health agents.
5. Design card-to-bookmark action.
6. Design card-to-todo/reminder action.
7. Write dashboard Web/Convex schema-gate note.

---

## Later

- First-class sources
- matched personalization signals
- freshness/expiration fields
- tags/facets separate from topics
- card-to-note/memory/event actions
- Web dashboard after schema approval
- mobile browse/action surface
- user-visible explanation/debug panel for “why this card?”

---

## Do Not Do Yet

- Generic RSS dashboard
- Web-only dashboard store
- Convex schema change without schema gate
- AI/news collectors before the manual/review loop is useful
- Silent card creation with weak personal relevance
- Bulk destructive dashboard cleanup
