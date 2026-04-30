# Contact Profile Surface Design

**Date:** 2026-04-30
**Status:** Approved design, implementation requested

## Summary

Redesign contact details so a contact can be the home for a person's useful context, not just a thin metadata card. The same contact profile must render with feature parity inside the normal Cider `NSWindow` and inside popped-out `NSPanel` surfaces.

The profile surface keeps important contact methods and facts visible, adds tabbed sections for deeper context, makes notes directly editable, and leaves room for related/backlinked items such as gift bookmarks, vacation ideas, restaurant links, todos, files, and date cards.

## Problem

Contacts currently feel small and generic. They can store useful fields such as birthday, relationship, phone, email, address, labels, and notes, but the detail view presents them as a compact appendix. In practice, richer person context ends up in a separate note, which splits one real-world person into multiple Cider items.

This also weakens floating panels. A popped-out contact card should feel like a useful profile, not a narrow metadata view. Notes surfaced in panels also have a reliability issue where the editor can fail to render content, likely because note editor state and the shared TipTap `WKWebView` are not owned predictably across surfaces.

## Goals

- Make contact details feel like a warm, useful profile surface.
- Keep feature parity between main-window contact details and floating contact panels.
- Make contact notes directly editable without opening a separate note card.
- Keep structured profile fields safe behind an explicit edit mode.
- Keep phone, email, address, birthday, relationship, labels, and other important facts visible across tabs.
- Add a `Related` section that can show existing linked entities and later grow into backlinks by person.
- Fix the floating note rendering path enough that popped-out notes reliably show selected note content.
- Keep the implementation scoped and compatible with existing `.vcf`, SQLite, and `LibraryEntityRef` storage.

## Non-Goals

- No full personal CRM system in this pass.
- No custom user-defined contact schema or unlimited arbitrary sections.
- No automatic AI inference of relationships or gift categories.
- No full backlink creation UI for every item type in this pass.
- No migration that deletes or mutates existing profile notes automatically.
- No redesign of bookmark, todo, date card, or vault file detail surfaces beyond the shared parity work needed here.

## Chosen Direction

### Contact Profile v1

Contacts should use a shared profile surface with a persistent identity header, tabbed content, and a persistent essentials area.

The header contains:

- avatar
- display name
- relationship label
- a lightweight birthday/age hint when birthday exists
- edit/done controls supplied by the surrounding detail panel chrome

The tab row contains:

- `Overview`
- `Birthday`
- `Favorites`
- `Notes`
- `Related`

`Overview` is the default tab. It shows a friendly profile summary from the contact notes and key preference fields. If the contact has sparse data, it should show a quiet empty state with an edit affordance instead of a blank panel.

`Birthday` shows birthday, age, next birthday, and linked birthday date card information when available.

`Favorites` shows person preferences such as favorite color, foods, activities, sizes, gift ideas, and other structured preference text. In v1 these can be derived from contact profile notes or stored in simple new contact fields if the implementation keeps storage small and backward-compatible.

`Notes` is directly editable. It replaces the separate "profile note" use case for everyday person context. The user should be able to type into notes without toggling the whole profile into edit mode.

`Related` shows linked items from `contact.linkedEntities`. In v1 it should at least render linked date cards, notes, bookmarks, todos, contacts, and vault files when resolvable. Later, this can grow into backlink creation and grouped sections such as gifts, trips, restaurants, preferences, and memories.

### Essentials

The persistent facts area should be called `Essentials`.

It remains visible across tabs when width allows, and contains:

- phone
- email
- address
- birthday and age
- relationship
- labels
- linked birthday date card status when useful

On narrow floating panels, `Essentials` becomes a collapsible disclosure block below the tab row. The collapsed state should still signal whether important details exist.

### Editing

The default profile is read-only and action-oriented. Phone/email/address should behave as information and eventual actions, not accidental text fields.

Clicking `Edit` enters profile edit mode for structured fields. Edit mode can expose text fields/date pickers for display name, relationship, birthday, phone, email, address, labels, and other structured fields. Saving persists through `ContactStorage.updateContact`.

The `Notes` tab is the exception. It can be directly edited in view mode because notes are where quick additions belong.

### Surface Parity

The profile content must be implemented as a shared SwiftUI view that both main-window detail containers and floating `NSPanel` detail containers use.

The parent shell may differ:

- main window uses the existing slide-out/full/page `GenericItemDetailPanel`
- floating panel uses `CiderFloatingPanel` plus `GenericItemDetailPanel`

The contact body, tabs, essentials behavior, edit behavior, and notes editing must be shared.

### Floating Note Reliability

Popped-out notes should reliably render their content. The current floating note path creates a separate `NotesViewModel` and uses the shared TipTap `WKWebView` pattern, which can fail when editor readiness and view ownership do not line up.

The fix should make floating note selection and editor content push deterministic. Acceptable v1 outcomes:

- the floating note editor uses a correctly initialized `NotesViewModel` that selects and pushes the note after the editor is ready, or
- the floating note surface uses a read/write source editor that does not compete for the singleton TipTap web view.

The chosen fix must preserve main-window note editing behavior.

## Data Model

Use the existing `ContactCard` fields first:

- `displayName`
- `relationshipLabel`
- `birthday`
- `notes`
- `email`
- `phone`
- `address`
- `hasAvatar`
- `labelIDs`
- `linkedEntities`

If v1 needs structured favorites, add a small backward-compatible field instead of inventing a large schema. A conservative option is:

```swift
var favorites: String
```

This can render as lightweight lines in the `Favorites` tab and later be upgraded if real usage demands more structure.

Any new stored field must round-trip through:

- `ContactCard` Codable
- `VCardSerializer`
- SQLite contact persistence
- mutation audit snapshots if applicable
- trash/restore payloads if applicable

## Related Items

The `Related` tab should resolve `LibraryEntityRef` values into display rows/cards using existing storage services:

- bookmarks from `VaultBookmarkService`
- notes from `NotesStorage`
- date cards from `DateCardStorage`
- contacts from `ContactStorage`
- todos from `TodoCardStorage`
- vault files from `VaultFileStorage`

Missing references should not crash the surface. They should render a small unavailable row or be filtered with a count of unavailable items, whichever fits existing Cider UI patterns better.

In v1, backlink creation can remain a follow-up. The important design move is that contact profiles have a clear home for linked items.

## Testing

Add focused tests for pure contact profile helpers:

- initials and display facts for sparse contacts
- birthday age and next-birthday behavior
- essentials visibility/collapsed summary behavior
- resolving linked entities into stable display models where practical
- note editing persistence through `ContactStorage.updateContact` if exposed through a small helper

Run targeted existing tests for contacts and floating surfaces.

Manual verification should cover:

- contact profile opens in main-window slide-out
- contact profile opens in main-window full/page modes
- contact profile opens in floating `NSPanel`
- tabs show the same content in embedded and floating modes
- Essentials remains visible or collapses appropriately by width
- structured edit mode saves and cancels correctly
- Notes tab edits persist
- Related tab shows linked date card for birthday contacts
- popped-out notes render content reliably

## Risks

- If notes editing is too custom, it could diverge from the normal note editor and surprise users.
- If structured favorites are over-modeled too early, contacts could become form-heavy.
- If Essentials takes too much width, narrow floating panels could feel cramped.
- If floating note editor state is changed too broadly, main-window note editing could regress.
- If related item resolution eagerly loads too much data, contact profiles could become heavier than expected.

## Follow-Ups

- Add backlink creation from bookmark/note/todo detail views to a selected contact.
- Add grouped related sections such as `Gift Ideas`, `Trips`, `Restaurants`, and `Preferences`.
- Add "save bookmark as gift idea for contact" from capture flows.
- Add contact profile note migration suggestions for folders that contain one contact plus one likely profile note.
- Add richer person widgets or desktop stickies once the profile surface proves useful.
