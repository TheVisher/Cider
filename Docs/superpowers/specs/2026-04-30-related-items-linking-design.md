# Related Items Linking Design

## Purpose

Cider should let contacts become useful hubs for the items that belong to a person: gift ideas, vacation links, favorite restaurants, notes, todos, date cards, and files. The first pass should support explicit manual and CLI/agent-created links. Smart suggested links can come later once the underlying link system is reliable.

## Scope

This design covers first-class item linking between active library item types:

- Bookmarks
- Notes
- Todos
- Date cards
- Contacts
- Vault files

Legacy entity types such as `externalFile` and `session` remain readable for backward compatibility, but new link creation should not target them.

## Product Behavior

Users should be able to link a saved item to a contact and then see that item on the contact card's Related tab. The same mechanism should support non-contact links so this can later power project, trip, recipe, and other hub-style pages.

The first implementation should prioritize:

- Linking any supported item to a contact.
- Showing both direct links and backlinks in the contact Related tab.
- Letting agents create, remove, list, and inspect links from the CLI.
- Keeping existing date-card/contact birthday links working.

Manual linking should begin with context-menu flows that fit the current app:

- Contact cards can link to other supported items.
- Bookmarks, notes, todos, date cards, and files can link to contacts.
- Existing "Linked Items" menus should continue to open linked targets.

## Architecture

Add an `ItemLinkService` as the central linking API. It should hide storage-specific details and give UI/CLI callers one place to perform link operations.

Responsibilities:

- Resolve item references by type and identifier.
- Create bidirectional links between supported items when both item models can store `linkedEntities`.
- Remove links from both sides.
- List outgoing links stored on an item.
- List backlinks from SQLite `item_links`.
- Return display summaries for linked items.

The service should use existing storage services rather than introducing a second source of truth. Item models that already own `linkedEntities` remain authoritative for their outgoing links. The SQLite `item_links` table is used for persistence, querying, and backlink lookup.

## Data Flow

### Link Creation

1. Caller requests a link between a source item and a target item.
2. `ItemLinkService` resolves both refs and confirms both are active entity types.
3. The source item receives a `LibraryEntityRef` for the target when its model supports `linkedEntities`.
4. The target item receives a `LibraryEntityRef` for the source when its model supports `linkedEntities`.
5. Each affected storage service persists its updated item, which refreshes `item_links`.
6. Duplicate links are ignored.

Vault files currently do not have `linkedEntities`. For the first pass, links involving vault files should be stored directly in `item_links` by `ItemLinkService`; vault files should not gain an outgoing `linkedEntities` property until there is a broader file-metadata reason to add one.

### Link Removal

1. Caller requests unlink between two refs.
2. `ItemLinkService` removes matching refs from each side that supports `linkedEntities`.
3. Each affected storage service persists its item.
4. Any direct `item_links` row used for non-owning item types is removed.

### Related Display

The contact Related tab should combine:

- Outgoing refs from `contact.linkedEntities`.
- Backlinks from `item_links` where `target_id == contact.id`.

The display should de-duplicate refs and resolve titles/subtitles/icons using the existing storage services. Missing stale targets should be skipped in normal UI.

## CLI / Agent Interface

Agents should be able to manage links without UI access.

Proposed commands:

```bash
cider-cli link add <source-type> <source-ref> <target-type> <target-ref> [--json]
cider-cli link remove <source-type> <source-ref> <target-type> <target-ref> [--json]
cider-cli link list <type> <ref> [--json]
cider-cli link backlinks <type> <ref> [--json]
cider-cli link related <type> <ref> [--json]
```

Definitions:

- `list` returns outgoing links.
- `backlinks` returns incoming links.
- `related` returns the merged outgoing-plus-backlink view used by contact cards.
- `ref` should accept UUID prefixes. For contacts it should also accept display names. For bookmarks, notes, todos, date cards, and files, title/name matching can be added conservatively where ambiguity is reported instead of guessed.

`--help` should work for `cider-cli link --help` and nested subcommands.

## UI

The first UI pass should stay compact and consistent with existing card context menus.

Context menus:

- Contacts: "Link Item..." with submenus for linkable item types.
- Bookmarks, notes, todos, date cards, vault files: "Link Contact..." as the primary high-value flow.
- Existing date-card/contact linking should move onto the shared service.

Contact Related tab:

- Show merged related items.
- Grouping can remain a simple flat list for the first pass.
- Each row should show icon, title, subtitle, and item type context.
- Rows should open the target item using existing detail/open flows where available.

## Error Handling

The service and CLI should fail conservatively:

- Unknown type: clear error listing supported types.
- Missing item: clear "not found" error.
- Ambiguous name/title: list matching IDs and ask for a more specific ref.
- Unsupported link direction: clear error explaining which type cannot own outgoing links.
- Duplicate link: no-op success.
- Missing stale target during display: omit from normal UI, but do not crash.

## Testing

Unit tests should cover:

- Type/ref resolution.
- Bidirectional link creation for models with `linkedEntities`.
- Duplicate links remain single.
- Link removal updates both sides.
- Backlink queries include links where the contact is only the target.
- Contact Related view-model/helper merges outgoing links and backlinks without duplicates.
- CLI help and JSON output shape.

Smoke tests should cover:

- Agent CLI links Baine to a bookmark and removes it.
- Contact Related tab shows a linked bookmark after restart.
- Existing birthday date-card/contact link still appears.

## Out Of Scope For First Pass

- AI suggested links.
- Automatic entity extraction from bookmark/note text.
- Link confidence scores.
- Link categories such as "gift", "restaurant", or "vacation".
- New visual graph views.
- Bulk link management UI.

These are good follow-ons once manual and agent-created links are trustworthy.
