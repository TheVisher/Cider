# Universal Metadata Inspector Design

**Date:** 2026-04-30
**Status:** Approved design, awaiting user review of written spec

## Summary

Add a universal metadata inspector rail for Cider item detail surfaces. The rail is opened with the same `i` affordance already used by bookmark details, compresses the main content area when visible, and provides a consistent home for backlinks, notes, labels, type-specific metadata, edit controls, and created/modified information.

For contacts, the rail also becomes the structured edit panel. The contact body remains a readable profile with important contact information visible, while the rail owns management tasks such as adding/removing structured fields, editing metadata notes, managing backlinks, and viewing item info.

## Problem

Cider item types expose metadata unevenly. Bookmarks already have a useful right-side metadata area, but contacts, notes, todos, date cards, and files have different patterns or no consistent place for the same concepts. This makes backlinks harder to discover and makes users learn a different surface for each card type.

Contacts now have a richer profile surface, but `Related` and `Notes` as primary tabs compete with the core purpose of the card: showing information about the person. The user wants backlinks and item notes to be consistently discoverable in metadata, while important person details remain visible in the contact card itself.

## Goals

- Give every supported detail surface the same metadata open/close affordance.
- Use one shared right rail pattern for backlinks, metadata notes, labels/folder, created date, modified date, and item type.
- Move contact backlinks out of the `Related` tab and into the metadata rail.
- Move contact metadata notes into the rail, matching bookmark notes.
- Keep important contact information visible in the contact body even when the rail is closed.
- Let the contact metadata rail become the edit surface for structured contact fields.
- Preserve feature parity between the main `NSWindow` detail surface and popped-out `NSPanel` detail surfaces.
- Keep the agent/CLI story aligned: anything the rail can structurally manage should also be manageable by agents where a CLI already exists or is being extended.

## Non-Goals

- No full redesign of each card body in this pass.
- No visual graph view for backlinks.
- No AI-suggested link creation.
- No bulk metadata editor.
- No schema-heavy CRM builder for contacts.
- No automatic migration that deletes existing notes or links without user action.

## Chosen Direction

### Shared Metadata Rail

Each detail surface should have an `i` button in the detail chrome. Clicking it toggles a right-side metadata rail. When open, the rail compresses the main content area instead of replacing it. When closed, the card body keeps its existing readable layout.

The rail should use a common section order:

- item title/header
- source or primary identity fields when applicable
- type-specific metadata
- linked/backlinked items
- metadata notes
- folder and labels when applicable
- created, modified, and type info
- destructive actions where the item type already supports them

The exact sections can be omitted when empty or not relevant. Empty universal sections should not create visual clutter unless they provide an obvious action, such as adding the first link or note.

### Contacts

The contact detail body remains the person's readable profile. Important contact facts belong in the card body, not only in metadata.

The body should show:

- avatar, display name, relationship, and birthday/age hint in the header
- `Overview`, `Birthday`, and `Favorites` tabs
- phone, email, address, birthday, relationship, favorite fields, and custom fields where present
- quiet empty states for missing optional data

The contact body should remove the `Related` tab. Backlinks and manually linked items live in the rail. The contact body should also remove the `Notes` tab for this pass. Contact notes are metadata notes and live in the rail.

### Contact Rail As Edit Panel

For contacts, the metadata rail is both an inspector and an edit panel.

In view mode, it shows:

- contact title
- essentials summary
- linked/backlinked items
- metadata notes rendered for reading
- labels
- created, modified, and type info

In edit mode, the same rail becomes the structured contact editor:

- edit display name and relationship
- edit birthday and birthday date-card preference
- edit phone, email, address
- add, rename, reorder, and delete custom structured fields
- edit metadata notes
- edit labels
- manage linked items where existing link UI supports it

The main body reflects saved structured fields. Unsaved edits should stay visually contained in the rail until the user saves.

## Data Model

Use the existing item models and link system first.

Contacts should continue to use the current `ContactCard` fields for known data:

- `displayName`
- `relationshipLabel`
- `birthday`
- `notes`
- `email`
- `phone`
- `address`
- `labelIDs`
- `linkedEntities`

Custom structured fields should use the smallest backward-compatible addition that supports user-added fields. A field needs:

- stable id
- label
- value
- optional kind, such as text, phone, email, url, date, address, or note
- display order
- optional pinned/important flag if needed for the contact body

The contact body should only render fields with values. Empty fields can exist while editing but should not clutter view mode.

Any new stored contact field must round-trip through contact persistence, card rendering, edit save/cancel, trash/restore payloads if applicable, and CLI JSON output.

## Backlinks

The metadata rail should use the shared related view: outgoing links plus incoming backlinks, de-duplicated and resolved into clickable rows.

Backlinks should appear in metadata for all supported item types:

- bookmarks
- notes
- todos
- date cards
- contacts
- vault files

Clicking a linked row should open the target item using the same detail routing used elsewhere. The opened item should show the original item in its own metadata rail through the reciprocal related view.

## Metadata Notes

Metadata notes are item-specific notes about the item, not necessarily the item body itself.

Bookmarks already use this pattern. Contacts should adopt the same pattern. Notes can still have their normal note body as the main content, but their metadata rail can also hold metadata notes if the underlying model supports it or if a follow-up adds that field.

Contact metadata notes should render Markdown in read mode and switch to an editor in rail edit mode. Raw Markdown should not leak into read-only metadata or card previews unless the user is actively editing Markdown.

## UI Behavior

The rail open state should be local to the current detail surface. A main-window detail and a popped-out panel can each control their own rail visibility.

On wide surfaces, the rail appears on the right. On narrow floating panels, the rail can use the same right-side pattern if space allows; otherwise it can slide over the content while keeping the same section order and edit behavior.

The card body should not be rebuilt around the rail. The first pass should add the common inspector shell and wire sections into each supported detail surface, keeping existing card layouts intact wherever possible.

## CLI / Agent Behavior

Agents should be able to manage data that the metadata rail exposes structurally.

The existing link CLI remains the agent path for backlinks:

- add links
- remove links
- list outgoing links
- list backlinks
- list merged related items

The contact CLI should support structured field management:

- add custom field
- update custom field
- delete custom field
- list fields
- update metadata notes

CLI operations should return JSON when requested and should fail clearly on ambiguous contact names, unknown field ids, unsupported field kinds, or missing items.

## Architecture

Introduce or extract a shared metadata inspector layer rather than copying bookmark metadata UI into every detail view.

Recommended units:

- `ItemMetadataInspectorView`: shared rail shell and common section layout.
- `ItemMetadataViewModel`: resolves title, type, timestamps, labels/folder, links, and metadata notes for a generic item ref.
- `ContactMetadataEditorView`: contact-specific inspector/editor content.
- Small per-type adapters for bookmark, note, todo, date card, contact, and vault file metadata.

The detail containers should own the rail open/closed state and pass the selected item/ref into the metadata view model. The inspector should call existing storage services through narrow helpers instead of directly embedding storage logic in SwiftUI views.

## Error Handling

- Missing linked targets should not crash the rail; show an unavailable row or omit with a quiet count if that matches existing UI.
- Failed saves in the rail should keep unsaved edits in place and show a visible error.
- Ambiguous CLI identifiers should list matches and require a more specific ref.
- Unsupported metadata sections should be omitted rather than shown disabled.
- Read-only or uneditable fields should render in view mode but not present editing controls.

## Testing

Unit tests should cover:

- common metadata section ordering and omission of empty sections
- merged outgoing plus backlink display rows
- contact custom field add/update/delete helpers
- contact metadata notes save/render path
- CLI structured field commands and JSON output
- rail state isolation between main-window detail surfaces and popped-out `NSPanel` detail surfaces

Manual verification should cover:

- bookmark metadata rail still works
- contact metadata rail opens and closes in the main window
- contact metadata rail opens and closes in an `NSPanel`
- important contact info remains visible when the rail is closed
- contact edit mode in the rail can add and delete a structured field
- contact metadata notes render as Markdown in view mode and save edits
- backlink rows appear in metadata for bookmarks and contacts
- clicking a linked row opens the target and shows the reciprocal related item
- notes, todos, date cards, and vault files show the shared metadata rail without breaking their existing body layouts

## Risks

- The rail could become too crowded if every possible section is always visible.
- Contact editing in the rail could feel cramped on small panels if the layout is not responsive.
- Adding custom structured fields requires careful persistence and CLI handling.
- If metadata notes are modeled inconsistently across item types, users may not understand which notes are item metadata and which notes are primary content.
- Reusing bookmark metadata code too directly could preserve bookmark-specific assumptions in other item types.

## Follow-Ups

- Add metadata-note support to item types that do not already have a clean notes field.
- Add link categories such as gift idea, vacation, restaurant, preference, and reference.
- Add smart link suggestions once manual links and backlinks are reliable.
- Add keyboard shortcuts for toggling the metadata rail and saving rail edits.
- Add richer per-type metadata sections after the shared inspector pattern is stable.
