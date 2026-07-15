# Cider CLI

Status: canonical core doc.

`cider-cli` is the shell and agent interface for Cider. It should be scriptable, conservative, and clear.

## Principles

- `--json` means strict JSON on stdout with no human-readable framing.
- Human-readable output is for non-JSON mode.
- Commands that mutate user data should report what changed.
- Agents should prefer CLI or app services over direct filesystem mutation.
- Destructive operations should use Cider safety flows.

## Common Agent Workflows

Use CLI commands for:

- Cider-owned capture, routing, review, and recall
- exact agent capture through `capture add`
- vault search and item lookup
- current vault totals and status checks
- Kanban card creation and movement
- board inspection
- database backup inspection
- focused regression checks

## Kanban

Kanban boards live in `~/CiderVault/.cider/boards/`.

Use supported `cider-cli board ...` commands for routine card creation, movement, milestone assignment, section updates, evidence, history, handoffs, and commit traceability. If a command lacks a needed routine operation, create a scoped follow-up to add the missing CLI command instead of normalizing direct YAML patching.

Raw board YAML edits are only for parser/storage debugging or emergency repair. Any direct board-file write must use structured parsing or a careful whole-file rewrite, then validate the board file and refresh projections when relevant.

Every card must include `created: 'YYYY-MM-DD'`.

## Second Brain v1 Agent CLI Surface

`cider-cli capture add` is the canonical agent capture API. Agents should use it for new notes, todos, bookmarks, files, events, contacts, and journal entries, and should include `--json` for verification. Use `--kind journal --stdin` or `--kind journal --text-file <utf8-text-file>` for journal text. Do not import staged journal Markdown/text files as file captures; reserve `--kind file --path <source-file-path>` for genuine user file artifacts.

Core capture flags:

- `--kind note|todo|bookmark|file|event|contact|journal` selects the item kind explicitly. Do not rely on inference when the kind is known.
- `--stdin` reads exact raw source text from standard input.
- `--text-file <path>` reads exact raw source text from a file.
- `--content <text>` reads exact raw source text inline for capture kinds that accept text, and remains accepted for daily append helpers when stdin is awkward.
- `--url <url>` is the explicit bookmark source.
- `--path <source-file-path>` is the explicit file source for `capture add`.
- `--folder <target-folder-path>` is the destination folder selector for `capture add`; examples include `Inbox/Notes`, `Inbox/Bookmarks`, and project or topic folders.
- `--json` is required for agent verification.

Folder/path rules:

- Source paths are local filesystem inputs. In `capture add`, `--path` always means source file, never destination.
- Target folders are vault-relative destination folders. Use `--folder "Inbox/Notes"` when capturing a note directly to the Notes inbox.
- Target paths in `item move`, `review correct`, and `route correct` are folder paths. `--path "Projects/Cider/Notes"` means move or route into that folder.
- Vault artifact paths include filenames such as `Inbox/Bookmarks/Example.webloc` or `Projects/Cider/Notes/Plan.md`. Do not pass artifact filenames to `item move --path`; pass the containing folder with `--folder Inbox/Bookmarks` or `--path Inbox/Bookmarks`.

Canonical examples:

```bash
printf '%s' "$RAW_NOTE" | cider-cli capture add --kind note --stdin --json
cider-cli capture add --kind note --folder "Inbox/Notes" "Quick note" --json
printf '%s' "$APPEND_TEXT" | cider-cli item update note <note-id> --append --stdin --json
cider-cli item update note <note-id> --title "New Title" --content "Replacement body" --json
printf '%s' "$RAW_TODO" | cider-cli capture add --kind todo --stdin --json
cider-cli capture add --kind bookmark --url "https://example.com?a=1&b=two" --json
cider-cli capture add --kind file --path "/path/with spaces.txt" --json
printf '%s' "$RAW_EVENT_DETAILS" | cider-cli capture add --kind event --title "Passport appointment" --date 2026-05-20 --time "10:30 AM" --location "City Hall" --stdin --json
printf '%s' "$RAW_CONTACT_NOTES" | cider-cli capture add --kind contact --name "Avery Example" --email avery@example.com --phone "555-0100" --stdin --json
printf '%s' "$RAW_JOURNAL" | cider-cli capture add --kind journal --date today --stdin --json
```

The capture JSON contract reports `command: capture.add`, source text/source metadata, item identity when available, routing/review state, provenance/indexing status, `nextSafeAction`, and `safeNextCommands`.

Hidden or removed legacy commands return `legacyRemoved: true` with a canonical replacement. Legacy type-specific commands such as `bookmark`, `note`, `todo`, `event`, `contact`, `file`, `folder`, `tag`, `label`, `dashboard`, `media`, `recall`, and top-level `search/query/recent/status/snapshot` are not part of the visible agent API.

`bookmark add`, `note create`, `todo create`, and `file import` are temporary compatibility wrappers. They should remain hidden from top-level help, call the capture backend, and return `compatibilityWrapper: true`, `backendCommand: capture.add`, and nested `capture.command: capture.add`.

`item update note <id-or-ref> [--title <title>] [--content <text>|--stdin|--text-file <path>] [--append] --json` is the blessed agent-safe mutation path for existing note edits. It writes through `NotesStorage`, updating the Markdown artifact, SQLite `items` / `notes`, note search chunks, and app-facing note read model together. Agents must use this path for ordinary note append/replace/rename work instead of editing `.md` files directly.

`capture add --kind journal [--date YYYY-MM-DD|today] [--time HH:mm] (--stdin|--text-file <path>|--content <text>|<journal text>) --json` is the blessed agent journal capture path. It appends readable Markdown to the daily journal note, derives `journalMetadata` sections/spans, records `capture_event` provenance, refreshes indexing/readback, and composes the existing Journal graph/memory extractor after the source commit. Safe HTTP(S) references plus precise place, person, and project mentions can become reviewable candidates anchored to the exact capture event, text source, quote, and span; unsafe or credential-bearing URLs are inert, and capture never auto-creates or auto-selects canonical entities. Candidate IDs and evidence/lifecycle rows are stable across exact retry and database reopen. JSON returns `graphCandidates` and enrichment state, uses `nextSafeAction: review_candidates` plus the existing Journal Intelligence/Review Queue commands when review is needed, and otherwise uses `inspect_item`; a post-commit candidate failure reports `partialSuccess` while preserving and truthfully reporting the committed Journal source. Add repeated `--media <local-path>` flags to make text plus all media one atomic source mutation; optional repeated `--media-title`, `--media-id`, and `--media-kind photo|audio|media` values pair by position, and `--idempotency-key` gives adapters an explicit stable retry identity. The media receipt returns the day item, text source, distinct media source cards, immutable original refs, raw filenames, friendly titles, retry state, and reviewable candidate receipt. Agents must not edit daily journal Markdown directly, and successful journal captures should not be routed into folder-review correction chores.

`note daily append --kind journal [--date YYYY-MM-DD|today] [--time HH:mm] (--stdin|--text-file <path>|--content <text>) --json` is a compatibility wrapper over `capture add --kind journal`; JSON returns `command: note.daily.append`, `backendCommand: capture.add`, nested `capture.command: capture.add`, and machine-readable guidance to prefer `capture add --kind journal`. `note daily append --kind food-log` remains the lower-level same-day append path for food logs.

`capture journal-cleanup --capture-event <capture-event-id> --json` is the supported cleanup path for mistaken/test journal captures. It removes the matching generated journal section, deletes the capture event provenance, and deletes only reviewable graph/memory candidates tied to that capture event; accepted graph or memory truth is not deleted.

`capture review-queue [--limit <n>] [--include-deferred] --json` is the agent-safe read-only capture worklist. It returns `command: capture.review-queue`, `readOnly: true`, `changed: false`, reason-code counts, item identity, severity/priority, provenance summaries, routing/review state, indexing/enrichment status, unsupported attachment summaries, and safe follow-up commands. It includes existing review queue items plus capture-health rows for unsupported attachments and missing or stale chunks. It does not approve, move, delete, or repair state by itself.

After capture, agents should verify and continue through backend-backed item/review commands: `item get`, `item search`, `item context`, `item relations`, `item backlinks`, `item move`, `item route`, `item link`, `review list`, `review approve`, `review correct`, `review enrich`, and `storage audit`.

`storage active-duplicate-invariants --json` is the canonical duplicate/integrity checker for active vault state. `storage restart-duplicate-regression --json` wraps that checker around the supported startup rebuild/reconcile path, returning pre/post snapshots, issue counts, new/resolved issue fingerprints, and `passed`/`status` fields so agents can detect restart-only duplicate, stale projection, and vault/SQLite drift regressions without parsing prose.

`review enrich <item-id> [--timeout <seconds>|--no-wait] --json` is the explicit bookmark metadata refetch path. Legacy bookmark-specific enrichment commands remain removed in favor of `review enrich` for one item and `review enrich-batch --confirm --json` for batches. Agent/CLI enrichment may fill a missing or low-information thumbnail, but must not replace an existing usable local thumbnail; thumbnail replacement is reserved for the app's user-initiated Refetch Metadata context menu. JSON output must report `command: review.enrich`, `status: completed|timed_out|scheduled`, before/after bookmark snapshots, changed metadata fields, wait timing when applicable, and safe follow-up commands. This lets agents tell the difference between a completed no-op, a still-pending WebView/native enrichment, and a blocked/partial metadata capture such as X/Twitter pages.

`cider-cli export folder <relative-path|id|Inbox> --format json|md [--limit <n>] [--json]` is the blessed bounded export path when an agent needs a shareable or tool-ingestable folder snapshot. JSON exports return `command: export.folder`, `readOnly: true`, `changed: false`, scope metadata, counts, stable `type:id` refs, item IDs, relative paths, related/backlink/provenance arrays, Markdown text, and safe follow-up commands. Markdown exports render item metadata and body text without requiring agents to scrape raw vault files. `export item <type> <id-or-ref>`, `export card <board-id/card-id|card-id>`, and `export project <project-id-or-name>` provide smaller bounded scopes. Whole-vault export is intentionally refused with structured JSON guidance; agents should increase `--limit` only after inspecting the scope.

## Important Command Areas

Keep command details in CLI help and tests, not sprawling docs. The core command areas agents rely on are:

- capture: `capture add --kind ... --json` for all new user material, plus `capture review-queue --json` for read-only capture worklists
- item: get/search/query/recent/context/relations/backlinks/graph-health/project-context/doctor, plus backend-backed update/move/unfile/route/link
- export: bounded folder/item/card/project export in JSON or Markdown; no unbounded whole-vault dumps
- review: list/summary/drilldown/approve/correct/defer/enrich/enrich-batch/jobs
- storage: audit/active-duplicate-invariants/restart-duplicate-regression/doctor-plan/doctor-apply/repair-schema
- route/routing: temporary routing aliases until consolidated
- migrate, doctor, and db integrity
- spaces: explain routing context and agent instructions
- boards: list, show, workflow, recent, testing-summary, parent-summary, children, card inspect, add-card, update-card, move-card, delete-card, section update, evidence add, history add
- database: backup list and isolated restore verification

## Item Graph And Spaces

Agents should prefer `cider-cli item ...` and `cider-cli space ...` for second-brain memory work.

Core commands:

- `item search <query> --json`: FTS-backed search over projected chunks. Explicit recall facets such as `type:file tag:ADHD` intersect broad item type/source intent with focused item tags. JSON results preserve the existing `id`, `kind`, `owner`, `title`, `snippet`, `rank`, `searchScope`, `item`, `createdAt`, `updatedAt`, `sourceRef`, `captureProvenance`, and `safeNextCommands` fields, and now add compact replay metadata for agents: `temporal` (`displayDate`, `sortDate`, `dateSource`, `dateConfidence`, plus item timestamps when available), `provenance` (`sourceRef`, `sourceType`, `sourceID`, `sourceTitle`, optional `sourceLocation`/`vaultRelativePath`, bounded `evidenceExcerpt`/`evidenceSummary`, and capture event/source IDs when available), `contextCommands`, and `verificationCommands`.
- Valid `item search --scope` values are `all`, `personalMemory`, `projectKanban`, `qaArtifacts`, and `files`. Use one scope value per search; do not combine scope names such as `personalMemory/all`. For the post-merge event-search smoke, use `cider-cli item search "event" --scope personalMemory --json` for life memory/date/event recall or `cider-cli item search "event" --scope all --json` for broad recall.
- Valid `item search --sort` values are `relevance`, `newest`, and `oldest`. Default `relevance` preserves matching order. Use `--sort newest` or `--sort oldest` only when recall is explicitly recency-oriented or when auditing/debugging temporal metadata; recency sorting uses each result's `temporal.sortDate`, which prefers capture provenance timestamps when present, otherwise item updated/created timestamps. Scoped/space JSON wrappers include `searchSort` and `sortExplanation`; default unscoped JSON remains an array. Example: `cider-cli item search "Panda Express" --sort newest --limit 5 --json`. Scoped example: `cider-cli item search "Panda Express" --scope personalMemory --sort newest --limit 5 --json`, then follow a result's `contextCommands[0]` such as `cider-cli item context note <id> --json` or verify with `verificationCommands[0]` such as `cider-cli item get note <id> --json`.
- Read-only recall chain and agent-safe diagnostics that return object-shaped JSON now include `actionReceipt`: `item.memory-recall`, scoped/space `item.search`, library `item.context`, library `item.get`, accepted-memory fact reads such as `item.memory-facts.list`, `item.memory-facts.inspect`, and `item.memory-facts.resurface`, recall-adjacent diagnostics/explainability surfaces including `item.search-debug`, `item.recall-context`, `item.due-to-surface`, and `item.why-surfaced`, plus `item.capability-map` and `item.graph-health`. The receipt is transient command output, not a durable mutation ledger. Fields include `command`, `commandFamily`, `subcommand`, `action`, `actor`, `readOnly: true`, `changed: false`, `timestamp`, `status`/`resultStatus`, `matchedCount` or diagnostic count when meaningful, `matchedSourceRefs`, `provenanceRefs`, `safeCommandRefs`, `verificationHint: "verify_with_safe_commands_and_source_refs"`, selector/fact context when applicable, and a truth boundary such as `receipt_proves_command_execution_not_memory_truth` or `receipt_proves_diagnostic_execution_not_graph_truth`. Some legacy explainability receipts also keep compatibility keys such as `sourceRefs`, `safeVerificationCommands`, and `safeNextCommands`. The receipt proves the read-only command execution and result provenance, not accepted memory truth, graph truth, or capability promotion. Default unscoped `item search <query> --json` remains array-shaped for compatibility and therefore has no top-level receipt; use `--scope all` or a narrower scope when a receipt-bearing search envelope is needed.
- Bounded graph/link mutation receipt coverage currently includes `item link <source-type> <source-ref> <target-type> <target-ref> --json`, which records a durable `link.add` action receipt in the shared action ledger for both successful mutations and structured failures/no-ops. Mutation receipts are additive JSON metadata with `command`, `commandFamily`, `subcommand`, `action`, `actor`, `readOnly: false`, `changed`, `status`/`resultStatus`, `timestamp`, `owner`/`ownerRef` when a source item resolves, `sourceRefs`, `evidenceRefs`, `safeVerificationCommands`, `safeNextCommands`, `safeCommandRefs`, `verificationHint`, and `truthBoundary: "receipt_proves_command_execution_and_mutation_outcome_not_memory_truth"`. Inspect recent mutation history with bounded read commands such as `cider-cli item action-ledger list --owner note:<id> --command link.add --json`, `cider-cli item action-ledger inspect <receipt-id> --json`, `cider-cli item context note <id> --max-history 10 --json`, or `cider-cli item recall-context --item note <id> --history-command link.add --json`. Receipts prove command execution and mutation outcome only; they do not promote semantic memory truth or accept candidate facts.
- Bounded review queue mutation receipt coverage currently includes `review approve <item-id> --actor agent --json`, `review defer <item-id> --json`, and `review correct <item-id> (--folder <name|path>|--path <target-folder-path>|--inbox) --json`, which record durable `review.routing.approve`, `review.routing.defer`, and `review.routing.correct` action receipts in the shared action ledger for successful routing-review mutations and structured missing-item failures. The receipts use `command` (`review.routing.approve`, `review.routing.defer`, or `review.routing.correct`), `commandFamily: "review"`, `subcommand` (`approve`, `defer`, or `correct`), `action` (`approve`, `defer`, or `correct`), `actor`, `readOnly: false`, `changed`, `status`/`resultStatus` (`accepted`, `deferred`, `corrected`, or `failed`), `timestamp`, resolved `owner`/`ownerRef`, source/evidence refs for the item and routing decisions when safe, `safeVerificationCommands`, `safeNextCommands`, `safeCommandRefs`, `verificationHint`, and `truthBoundary: "receipt_proves_command_execution_and_review_state_outcome_not_memory_truth"`. Inspect with `cider-cli item action-ledger list --owner bookmark:<id> --command review.routing.approve --json`, `cider-cli item action-ledger list --owner bookmark:<id> --command review.routing.correct --json`, `cider-cli item action-ledger list --owner bookmark:<id> --command review.routing.defer --json`, `cider-cli item action-ledger inspect <receipt-id> --json`, `cider-cli item context bookmark <id> --max-history 10 --json`, or `cider-cli item recall-context --item bookmark <id> --history-command review.routing.approve --json`. Review receipts prove the command ran and the review-state outcome was recorded; they do not prove semantic memory truth, promote candidate facts, or accept routing/candidate claims as truth.
- `item preference-recall <natural question>|--query <natural question> --json`: read-only natural preference/item recall over journaled and captured items. It uses item search/context evidence, returns concise cited observations plus `safeNextCommands`, and keeps source-backed observations distinct from accepted memory truth. JSON includes backward-compatible `summary`, `answer`, `citations`, and `safeNextCommands` fields plus bounded `candidates` entries with stable owner/item refs, `evidenceKind`, `claim`, `citationRefs`, `score`, `rankReason`, and `truthBoundary`. Saved places-to-try can appear as `source_backed_candidate`, not accepted preference truth.
- `item memory-recall <natural question>|--query <natural question> --json`: read-only natural personal/work memory recall over Cider notes/captures/items. It reuses the preference recall JSON contract while returning `command: "item.memory-recall"`, `answer.kind: "natural_memory_recall"`, and `answer.text`/`summary` with a concise source-backed answer when evidence is clear. `intent` includes `originalQuery`, `normalizedQuery`, `semanticQueryTerms`, optional bounded `factFamily` values such as `clothing_size_fit`, `tool_gadget_preference`, `health_care_note`, or `work_schedule_fact`, optional `factTarget`, and `searchQueries`; top-level `rankingExplanation` describes why candidates ranked. Candidates use source-backed owner/item refs, `evidenceKind` such as `source_backed_memory_observation`, compact `claim`/`snippet`, `citationRefs`, `score`, `rankReason`, `matchedSemanticTerms`, `matchExplanation`, `truthBoundary`, review status, and safe replay commands. Memory candidates also include compact `provenance` metadata so agents can verify without parsing prose: `sourceRef`, `sourceType`, `sourceID`, `sourceTitle`, optional vault-relative `sourceLocation`, `evidenceExcerpt`, `evidenceSummary`, `citationRefs`, `contextCommands`, and `verificationCommands`. Top-level `verificationCommands` replay the recall result into item context/get inspection. Zero-result responses can include `broaderSearchCommand` plus `fallback.safeNextCommand`, `fallback.safeNextCommands`, and `fallback.nextContextCommandShape` for a broader source search while preserving `source_lookup_not_memory_truth`. This is an agent-agnostic recall bridge, not a Hermes cache or accepted-truth store.
- `item search-debug <query> --json`: read-only recall diagnostics for agents. Returns exact item/chunk matches, matched chunk context, routing/provenance where available, tag facet filter stages, missing or stale index warnings, semantic/vector availability status, machine-readable warnings/errors, safe follow-up commands, and a compact `actionReceipt`. No-match or warning-only diagnostics still receive a read-only receipt with `matchedCount: 0`; the receipt proves the diagnostic command ran, not that diagnostic hypotheses are accepted memory truth. It does not repair or mutate indexes.
- `item recall-context (--item <type> <id-or-ref>|--query <topic>) --json`: read-only source-backed recall bundle for agents. Success JSON includes anchors, content blocks, accepted facts, `acceptedMemoryFacts`, reviewable candidates, action history, safe follow-up commands, and `actionReceipt` metadata over the anchor/source refs surfaced by the command. Accepted memory fact entries are additive to the legacy `acceptedFacts` array and include `surfacingRelevance` with stable `factID`/`factRef`, `candidateRef`, source refs/citations, relevance reasons, truth/candidate boundaries, context commands, and verification commands. Reviewable memory candidates remain in `reviewableCandidates` only and are not promoted to accepted truth. Structured selector/no-match failures also include a failed read-only receipt so agents can replay safe follow-up commands without promoting failed diagnostics to truth.
- `item journal-intelligence --date YYYY-MM-DD --json`: deterministic read-only daily Journal receipt over canonical stored graph and memory candidates. It counts only active proposals that pass the existing Review Queue wording gate, a confidence threshold, useful-category mapping, exact `capture_event.source_text` quote/span verification, and timestamped Journal-section matching. JSON groups proposals into people, places, activities, preferences, commitments, tasks, artifacts/media, trip plans, and durable memory; project references use durable memory rather than a new review category. Every proposal carries Journal owner, capture event, section, timestamp, candidate type, confidence reason, review/proposal state, non-truth boundary, exact source quote/span, and safe review commands. The additive `crossTimeReconciliation` object compares supported proposals with existing canonical people, places, projects, tasks, media/artifacts, trip plans, preferences, and accepted memories. Exact duplicate person/project matches remain ambiguous; a unique exact match is only a likely match and never an automatic link. It reports `status`, an optional classification of `repeat`, `new_update`, `correction_or_conflict`, or `genuinely_new`, at most three `likelyMatches` with stable canonical refs/kinds, bounded confidence/match strength, explicit evidence/reasons and read-only replay commands, plus `classification_withheld` explanations for ambiguous, unsupported, or incomplete bounded scans. `canonicalFamilyScans` makes each relevant family’s limit, loaded count, completeness, and truncation state explicit; a no-match result becomes `genuinely_new` only when every relevant family scan is complete, otherwise classification is withheld with stable truncation reasons. Activities and commitments remain unclassified until they have a bounded canonical family. Terminal, low-confidence, vague, negated, corrected, duplicate, uncategorized, or unverifiable candidates appear only in `suppressions` with reason codes and do not inflate `proposalCount` or the “Cider found N things worth reviewing” statement. The command never extracts, records or persists reconciliation, accepts, rejects, defers, creates links/tasks/entities/relations/facts, or rewrites data.
- `item due-to-surface [--limit <n>] [--stale-after-days <n>] [--include-suppressed] --json` and `item memory-facts resurface [--fact <candidate-id>] --json`: read-only resurfacing feeds. Accepted-memory rows keep existing candidate fields and add `surfacingRelevance` with `context: "due_to_surface"`, stable fact/candidate refs, source refs/cited evidence, relevance reasons, `truthBoundary: "accepted_memory_fact"`, `candidateBoundary: "reviewable_memory_candidates_excluded"`, and replayable context/verification commands such as `item recall-context` and `item memory-facts inspect`. The command envelopes include additive read-only `actionReceipt` metadata with `readOnly: true`, `changed: false`, selected fact/candidate refs, selector context for `--fact`, source/provenance refs, and replayable `safeCommandRefs`; failed accepted-memory selectors also include failed receipts without promoting reviewable candidates. Mixed feeds may also include reviewable candidates with their own non-truth boundaries.
- `item get <type> <id-or-ref> --json`: unified item context for library item refs such as bookmark, note, todo, dateCard/event, contact, and vaultFile, including `captureProvenance` when a capture event produced the item. Library item JSON includes an `actionReceipt`; legacy owner fallback JSON remains deprecated and receipt coverage is best-effort.
- `item owner-get <owner-type> <owner-id-or-ref> --json`: legacy owner-section inspection for projected owners such as Kanban cards; returns structured sections, routing decisions, agent actions, and owner resolution metadata.
- `item owner-get folder <id|path|name|Inbox> --json`: blessed read-only folder metadata inspection. Returns folder ID/name/path, parent/root flags, icon/cover metadata, direct and descendant folder/item counts by type, health flags for missing/ghost directories, and `safeNextCommands` for search, move, route, storage audit, and doctor planning.
- `item open <type> <id-or-ref> --json`: read-only UI bridge for surfacing a resolved library item, Kanban card, or board in the running Cider app. It posts `cider.externalOpenRequest` through `DistributedNotificationCenter`; JSON confirms the notification was posted, not that a human saw the target.
- `item capability-map --json`: read-only static capability contract for agents. JSON preserves existing top-level fields such as `purpose`, `generatedBy`, `areas`, `nextActions`, and `relatedRoadmapCards`, and additively includes `actionReceipt` with capability refs, safe diagnostic follow-ups, and `truthBoundary: "receipt_proves_command_execution_not_memory_truth"`.
- `item graph-health --json`: read-only graph readiness across owner relations, projects, capture events/attachments, content chunks, enrichment outputs, similarity candidates, schema state, counts, findings, string `suggestedCommands`, and structured `suggestedActions` / per-component `safeNextActions` with `readOnly`, `requiresApproval`, and `mutationReason` metadata. JSON preserves existing top-level fields and additively includes `actionReceipt` with component refs, `diagnosticCount`, safe diagnostic follow-ups, and `truthBoundary: "receipt_proves_diagnostic_execution_not_graph_truth"`; suggested repair commands remain separate from receipt proof and require their own approval path.
- `item project-context <project> --json`: project graph context with project owner, board/card/doc/artifact relations, backend project metadata, and safe follow-up commands. This is read-only; JSON reports `readOnly: true` and `changed: false`.
- `item sync-project <project> --json`: explicit project workspace sync/seed path for backend project metadata and Kanban owner relations. This can mutate state; JSON reports `readOnly: false`, `changed`, and `mutationReason`.
- `item route <type> <id-or-ref> --target-type <space|folder|board> --reason <text> --json`: records a routing decision without silently moving files.
- `item route ... --target-type space` records native Space membership and creates a `belongs_to_space` owner relation so item context and graph inspection can see the Space assignment.
- `item move <type> <id-or-ref> --path <target-folder-path> --json`: moves an item into a folder path. The path must be a folder, not a `.webloc`, `.md`, `.ics`, `.vcf`, or other artifact filename.
- `item delete <type> <id-or-ref> --reason <text> --json`: previews a trash-backed item deletion through the typed Cider storage APIs. The preview is read-only, returns `approvalRequired`, a deterministic `requiredApprovalToken`, `safeNextCommands`, and the full before snapshot. Only `--approve <token> --execute` performs the mutation, records mutation audit and agent-action evidence, and returns the trash item ID. Agents should use this for cleanup-safe dogfood or matrix runs instead of raw filesystem or SQLite deletion.
- `item rebuild-index --json`: rebuilds the all-library vault index cache from current typed storage services. Use this after cleanup or storage repair when the app still shows stale zombie cards from `.cider/index.json`; JSON reports before/after counts plus removed stale IDs.
- `capture add --test-run <run-id> [--test-marker <text>] ... --json`: records the created capture item in `.cider/test-runs/<run-id>.json` and returns `testRun.cleanupCommand`. Use this for agent dogfood or real-vault QA captures that must be removable later.
- `test-run cleanup <run-id> --dry-run --json`: previews manifest-backed cleanup for an agent test run. It refuses fuzzy cleanup when the manifest is missing, returns a deterministic approval token, and only lists items recorded by that run.
- `test-run cleanup <run-id> --approve <token> --execute --json`: moves only manifest-owned active items to Cider trash through typed item APIs, records mutation audit and agent-action evidence, prunes/rebuilds the all-library index, updates cleanup status in the manifest, and reports verification counts.
- `item batch-plan --stdin --json`: validates a JSON object with an `operations` array for multi-item `move`, `unfile`, `route`, and `link` planning. The plan step is read-only, returns per-operation status, `approvalRequired`, `requiredApprovalToken`, `nextSafeAction`, and `safeNextCommands`, and must be shown to the user before any batch mutation.
- `item batch-apply --stdin --approve <token> --execute --json`: applies an approved batch through existing typed item mutation APIs. Supports `move`, `unfile`, `route`, and `link`; route/link apply paths use backend routing/link services rather than raw storage edits. JSON returns per-operation before/after, routing, or link payloads, mutation audit IDs where available, partial failures, and rollback/repair guidance.
- `item backfill-kanban [--board <name-or-id>] --json`: rebuilds Kanban card projections from YAML into SQLite sections/chunks.
- `item dogfood-intelligence [--limit <n>] --json`: bounded mutation that rebuilds reviewable enrichment outputs and similarity candidates from existing content chunks. Generated rows remain `suggested`; accepting similarity candidates is a separate explicit command.
- `item doctor --json`: checks second-brain tables and SQLite integrity.
- `space explain <name-or-id> --json`: returns purpose, routing hints, default views, and agent instructions for a Space.
- `space list --json` and `space explain <name-or-id> --json` expose an `authority` object so agents can distinguish Space metadata, semantic membership, and storage fallback. `authority.pathContainmentIsSemantic: false` means root paths are not proof of membership.
- `media identify --dry-run --json`: read-only media identification preview. JSON reports `command: media.identify`, `readOnly: true`, `changed: false`, candidate counts, review items, and safe review actions.
- `media identify --apply --json`: mutating media identification apply path. JSON reports `command: media.identify`, `readOnly: false`, `changed`, `mutationReason`, write counts, and `actionRecords` for recorded media provenance. `actionRecords[].safeCommands` points agents at `item owner-get media_item <id> --json` and item search for the projected media owner.

Graph-heavy commands should expose counts and safe follow-up commands. Prefer bounded summaries or explicit full-detail flags when relation-heavy responses, such as project card lists, would otherwise flood agent context.

`item get` still accepts legacy non-library owner refs as a deprecated compatibility fallback and marks JSON with `command: item.get.legacy-owner-fallback`, `deprecated: true`, and a `deprecationMessage`. New callers should use `item owner-get` for owner projections and `item context`/`item get` for unified library items.

The second-brain command surface should support the product loop: capture -> enrich -> route -> review -> resurface/act. JSON output should make uncertainty, provenance, and next safe action visible.

Review queue JSON includes `reasonCodes` for trust-boundary states such as `routing_low_confidence`, `enrichment_failed`, `inbox_unrouted`, and duplicate-specific codes so agents do not need to parse prose reasons.

Media identification is a bridge command over file-backed MediaItem metadata. `media identify --dry-run --json` reports `readOnly: true` and `changed: false`; `media identify --apply --json` reports `readOnly: false` and must include a mutation reason when applying proposed YAML writes. Apply also refreshes bounded `media_item` owner sections/chunks so agents can inspect the bridge through `item owner-get media_item <id> --json` and discover it through `item search`. `reviewLane.safeActions` must include only read-only commands; mutating follow-ups belong in `reviewLane.actions` with `readOnly: false` and `requiresApproval: true`.

Database admin commands with `--json` use explicit envelopes. `db integrity`, `db backups`, and `db audit` report `readOnly: true` and `changed: false`; `db backup` reports the created backup and verification details with `readOnly: false`. `db restore <selector> --dry-run --json` is the agent-safe inspection path and reports the selected backup, required `--yes` confirmation, active-app blockers, planned pre-restore snapshot, rollback guidance, and safe follow-up commands. Confirmed restore can still refuse with structured JSON when Cider.app is running.

Kanban read commands with `--json`, including `board list`, `board show`, `board workflow`, `board recent`, `board testing-summary`, `board parent-summary`, `board children`, and `board card inspect`, use a stable read envelope with `ok`, `command`, `readOnly: true`, `changed: false`, board/card identity where applicable, and `safeVerificationCommands`. Command-specific bodies remain nested, such as `boardDetail`, `workflow`, `testingSummary`, and `parentSummary`, so agents do not need raw YAML or prose scraping.

Kanban card details can be discovered with `board recent <board> --limit <count> --json`, which lists newest card activity with board, column, parent, priority, timestamps, recent edit/move/completion activity kind, and compact current-state/next-step context. `board workflow <board> --json` groups workflow lanes and exposes approval-aware `automationActions` with safe inspection, history, move, and review-routing commands; these actions are guidance, not an agent scheduler. Testing gates can be triaged with `board testing-summary <board> --json`, which groups cards in Testing/Ready to Test columns into `needsErik` and `agentCanVerify` queues. Parent plan status can be inspected with `board parent-summary <board> --card <id> --json`; `--refresh --dry-run` returns proposed Current State / Next Step text and stale-parent findings, while `--refresh --confirm` applies those sections explicitly. Milestones are card-backed project checkpoints managed through `board milestone create <board> --title <title> --description <text> --json`, `board milestone list <board> --json`, `board milestone inspect <board> --milestone <id> --json`, and `board milestone attach-card <board> --milestone <id> --card <id> --json`; attach validates the relationship and records the milestone move on the card. Exact cards can be inspected through `board card inspect <board> --card <id> --json`, which returns parsed dashboard lanes, sections, card metadata, hierarchy, roadmap `roadmapNextUp` sequence/groups, links, routing decisions, and agent actions. Card details can be edited through `board section update <board> --card <id> --section <name> --value <text>`, `board evidence add <board> --card <id> --text <text>`, and `board history add <board> --card <id> --type <implementation|failed-attempt|test|decision|handoff|commit> --text <text>`. `board add-card <board> --column <col> --title <title> --parent <card-id> --after <sibling-id>` inserts a roadmap child immediately after an existing sibling in the same column. These update the YAML card and refresh its SQLite projection.

Normal agent workflow for a Cider card:

1. If the active card ID is unknown, run `board recent <board> --limit 20 --json` before broad search or raw YAML inspection.
2. Run `board workflow <board> --json` when choosing the next agent-safe action or review route for Queued/In Progress/Testing/Needs Fix cards.
3. `board card inspect <board> --card <id> --json` to understand state without scraping YAML.
4. `board section update ... --section "Current State" --value "..." --json` before and after implementation when state changes.
5. `board history add ... --type implementation --text "..." --source "..." --json` for concise implementation or fix summaries.
6. `board history add ... --type failed-attempt --text "..." --source "..." --json` when an attempted path matters for future agents.
7. `board evidence add ... --text "..." --source "..." --json` after verification. `board history add ... --type test` writes the same durable test-evidence lane.
8. `board history add ... --type decision --text "..." --source "..." --json` when a durable product, architecture, storage, CLI, QA, or agent-behavior choice is made.
9. For implementation work with repo changes, commit the scoped changes before moving the card to Done unless the user explicitly says not to commit.
10. `board history add ... --type commit --text "<sha> <branch/files/tests summary>" --source "git" --json` after committing, so Done cards can be traced to landed code.
11. If work is verified but intentionally uncommitted, record that state on the card and keep it out of Done.
12. `board history add ... --type handoff --text "..." --source "..." --json` before stopping, or use `board section update ... --section "Agent Handoff" --value "..." --json` for a full replacement handoff.

Kanban projection lifecycle:

- Creation: `board add-card`, `board update-card`, `board section update`, `board evidence add`, and `board history add` refresh that card's SQLite projection after writing YAML.
- Refresh: `item backfill-kanban --board <board> --json` rebuilds all card projections for a board from canonical YAML; omit `--board` to refresh every board.
- Deletion: deleting a Kanban card or board removes its projected sections/chunks so `item search` stops finding stale card content.
- Restore/reload: restored or reloaded boards should be followed by `item backfill-kanban --board <board> --json` when an agent needs fresh search immediately.
- Doctor: `item doctor --json` checks schema and table health. Projection drift detection is a follow-up, so suspected stale card projections should currently be repaired with backfill and verified with `item owner-get card <id> --json` plus `item search <query> --json`.

## Agenda And Life-Assistant Reporting

Agent reports should reduce noise, not turn every dated item into an alarm. This belongs in Cider's shared CLI/API layer so Dashboard, agents, and scheduled jobs get the same relevance answer without prompt-specific workarounds.

- Add or maintain a canonical agenda/briefing query path that returns agent-ready items with resolved relevance/status, not just raw todo/event records.
- The daily brief should focus on items important/relevant today, plus reminders whose configured reminder rule says to surface today.
- Active todos should come from backend-backed item/review/agenda queries, not legacy type-specific todo list output.
- If a completed todo matches a same-cycle date card or event, reports should not keep calling the dated item overdue. Example: completed `Pay rent` suppresses a same-title `Pay Rent` event for that cycle.
- Rent/monthly bills should only appear when the next due date is close, roughly within five days, or when the configured reminder rule says to surface today.
- Birthdays/anniversaries should not appear in every daily report merely because they are future dated. Cider should support reminder policies such as "one week before," "on the day," or "start-of-month birthday digest," and the agenda API should return `surfaceToday`, reason, reminder policy, and next surface date.
- The same reminder should not spam every daily report across its lead window unless explicitly configured as a repeating reminder.
## Current Hardening Cautions

Historical CLI and storage bug detail belongs on Kanban cards, not in this core doc. Durable cautions for agents:

- After CLI capture while Cider.app is running, verify the final item with duplicate/search/get commands instead of assuming a single row exists.
- Inbox can be virtual or type-scoped. Prefer item/review/storage JSON over raw folder lookup when reporting Inbox health.
- Duplicate folder/note/bookmark regressions should be audited against the current second-brain backend before cleanup. Use the current roadmap/bug cards for exact evidence and acceptance criteria.
- CLI/date handling must preserve local-date semantics for all-day events, birthdays, due dates, and Kanban `created` dates.

## CLI Quality Bar

When fixing or adding CLI behavior:

- add focused tests where practical
- preserve existing human-readable output unless intentionally changing it
- verify JSON output with a parser
- keep command errors actionable
