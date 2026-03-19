# Kanban Board — Vision

## Concept

A file-backed Kanban board in Cider where both the user and AI agents can read and write to the same board. The visual lives in Cider, the data lives on disk as a YAML file in the vault.

## How it works

**User → Cider UI:**
- Drag a card from Todo → In Progress
- Cider writes that change to the YAML file on disk

**Agent → YAML file:**
- Agent reads the YAML, sees what's In Progress
- Builds the feature
- Moves the card to Testing
- Cider reflects it instantly

## File format: YAML

YAML hits the sweet spot:
- Human readable — power users can edit directly
- Structured enough to render a proper visual Kanban
- AI can easily read and update — "move X to done" is trivial
- Git diffs are clean and meaningful
- Extends easily — add priority, tags, notes per card without breaking anything

## Example

```yaml
board: Cider iOS
columns:
  backlog:
    - id: m12
      title: Bulk Operations
      notes: Multi-select mode + bulk actions bar
      platform: iOS
      milestone: 12

  in_progress:
    - id: m11-search
      title: Search result highlighting
      platform: Web
      phase: 5.1
      agent: web-agent

  testing:
    - id: share-ext
      title: Share Extension fixes
      platform: iOS

  done:
    - id: tag-mgmt
      title: Tag management
      platform: iOS
      completed: 2026-03-17
```

## Agent rules

Agents could have a rule: "before starting work, read kanban.yaml and only work on cards assigned to you in in_progress. When done, move your card to testing."

Combined with a daily briefing, the agent wakes up, reads the Kanban, knows exactly what to do, and documents its own progress.

## Why this matters

- No Jira, no Notion, no Linear — just a YAML file and Cider
- Self-updating project board that both user and agents read/write simultaneously
- Fits Cider's open file format philosophy perfectly
- Columns are fully customizable (backlog, todo, in_progress, testing, done, or whatever)

## Status

Idea stage. Not yet implemented.
