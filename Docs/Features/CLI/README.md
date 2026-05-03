# CLI Feature

**Status:** Feature folder seed.

## Purpose

Cider CLI is the safe automation surface for agents and scripts. Agents should prefer CLI commands over direct vault/index mutations whenever possible.

## Code areas

- `Sources/CiderCLI/`
- CLI serializers in `Sources/CiderCLI/JSONOutput.swift`
- CLI model payloads such as `Sources/CiderCLI/DashboardCLIModels.swift`

## Rule

When a Cider operation has a CLI command, agents should use that command instead of editing storage files directly.
