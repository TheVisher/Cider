# Dashboard CLI

**Status:** Durable CLI reference for dashboard-related `cider-cli` commands.

---

## Command Group

```bash
cider-cli dashboard ...
cider-cli dash ...
```

Use `--json` whenever an agent needs machine-readable output.

---

## Topics

```bash
cider-cli dashboard topic list [--json]
cider-cli dashboard topic upsert --title <title> [--id <id>] [--icon <sf-symbol>] [--position <n>] [--color <token>] [--pinned true|false]
cider-cli dashboard topic move <id|title> --position <n>
cider-cli dashboard topic archive <id|title>
```

---

## Cards

```bash
cider-cli dashboard card list [--topic <id|title>] [--include-hidden] [--json]
cider-cli dashboard card upsert --json-file <path|-> [--json]
cider-cli dashboard card upsert --title <title> --summary <summary> --topic <id|title> [--source-url <url>] [--priority low|normal|high|urgent]
cider-cli dashboard card move <card-id> --topic <id|title> [--topic <id|title> ...]
cider-cli dashboard card seen <card-id>
cider-cli dashboard card dismiss <card-id>
cider-cli dashboard card archive <card-id>
cider-cli dashboard card delete <card-id>
cider-cli dashboard card feedback <card-id> [--more-like-this|--less-like-this|--clear-preference] [--rating 1-5]
```

---

## Agent Rules

Agents should use CLI/storage flows instead of directly editing:

```text
.cider/dashboard/_cider_dashboard.json
```

Use CLI for:

- listing cards/topics
- creating/upserting proposed cards
- marking seen/dismissed
- applying feedback
- moving cards between topics

Do not use CLI to silently create noisy/generic cards. If card relevance is below ~90%, ask or report first.

---

## Good Agent Card Payload

A good dashboard upsert should include:

- clear title
- concise summary
- `whyItMatters`
- source kind/title/URL or related Cider item
- topic routing
- priority
- provenance through a run when available

---

## Related Files

- `Sources/CiderCLI/DashboardCLIModels.swift`
- `Sources/CiderCLI/CiderCLI.swift`
- `Sources/CiderCLI/JSONOutput.swift`
- `Docs/Features/Dashboard/DATA_MODEL.md`
