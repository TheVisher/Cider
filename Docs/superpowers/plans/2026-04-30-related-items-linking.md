# Related Items Linking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class, reciprocal related-item links so contacts and other items can show and open linked/backlinked items, with CLI support for agents.

**Architecture:** Add `ItemLinkService` as the central API for resolving refs, writing/removing links, querying outgoing/backlink/related refs, and producing display summaries. Models with `linkedEntities` continue to own outgoing links; bookmarks, notes, and vault files use direct `item_links` rows.

**Tech Stack:** Swift, SwiftUI, SQLite via `CiderDatabase`, existing storage services, Swift Testing, `cider-cli`.

---

### Task 1: Core Link Service

**Files:**
- Create: `Sources/Cider/Services/ItemLinkService.swift`
- Test: `Tests/CiderTests/ItemLinkServiceTests.swift`

- [x] Write failing tests for active type parsing, direct SQLite link insert/remove, outgoing/backlink/related de-duplication, and summary resolution.
- [x] Run `swift test --filter ItemLinkServiceTests` and confirm failure because `ItemLinkService` is missing.
- [x] Implement `ItemLinkService` with `addDirectLink`, `removeDirectLink`, `outgoingRefs`, `backlinkRefs`, `relatedRefs`, `summary(for:)`, and type parsing.
- [x] Run `swift test --filter ItemLinkServiceTests` and confirm pass.

### Task 2: CLI Link Commands

**Files:**
- Modify: `Sources/CiderCLI/CiderCLI.swift`
- Create: `Sources/Cider/Services/ItemLinkCLIHelpText.swift`
- Test: `Tests/CiderTests/ItemLinkCLIHelpTextTests.swift`

- [x] Write failing tests for link CLI help text.
- [x] Add top-level `link` command support for `add`, `remove`, `list`, `backlinks`, `related`, and `--help`.
- [x] Return JSON when `--json` is present.
- [x] Run `swift test --filter ItemLinkCLIHelpTextTests` and `swift build --product cider-cli`.
- [x] Smoke-test `cider-cli link --help` and a reversible Baine bookmark link.

### Task 3: Contact Related Backlinks

**Files:**
- Modify: `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
- Modify: `Sources/Cider/Views/Contacts/ContactDetailView.swift`
- Test: `Tests/CiderTests/ContactProfileModelsTests.swift`

- [x] Write failing tests for merging outgoing refs and backlinks without duplicates.
- [x] Move related-item merge logic into a helper that uses `ItemLinkService.relatedRefs`.
- [x] Update the Contact Related tab to use merged related refs and summaries.
- [x] Run `swift test --filter ContactProfileModelsTests`.

### Task 4: Card Metadata And Context Menus

**Files:**
- Modify: `Sources/Cider/Views/Shared/FolderDetailView.swift`
- Modify: `Sources/Cider/Views/SavedViews/SavedViewTabContent.swift`
- Modify: `Sources/Cider/Views/Contacts/ContactCardCardView.swift`

- [x] Replace existing date-card/contact link helper with `ItemLinkService`.
- [x] Add "Link Contact" menu entries for bookmarks, notes, todos, date cards, and vault files.
- [x] Add "Link Item" menu entries for contacts.
- [x] Show compact linked-item metadata where card layouts already have metadata/footer space.
- [x] Ensure linked item menu rows still open the target item.

### Task 5: Verification

**Files:**
- No new files.

- [x] Run focused tests: `swift test --filter ItemLinkServiceTests && swift test --filter ItemLinkCLIHelpTextTests && swift test --filter ContactProfileModelsTests`.
- [x] Run `swift build --product cider-cli`.
- [x] Run a reversible CLI smoke test linking Baine to an existing bookmark and removing it.
- [ ] Run `xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build`.
- [ ] Restart Cider from `.deriveddata/Build/Products/Debug/Cider.app`.
