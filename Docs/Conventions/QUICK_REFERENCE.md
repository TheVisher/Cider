# Cider Quick Reference (For You)

## Slash Commands

| Command | What it does | When to use it |
|---------|-------------|----------------|
| `/update-vision` | Reviews the session and updates tab vision docs | After brainstorming features or making design decisions |
| `/revise-claude-md` | Reviews the session and updates CLAUDE.md | After discovering code patterns, gotchas, or conventions |
| `/feature` | Walks through adding a new feature (settings, model, VM, view) | Starting a new feature from scratch |
| `/feature-dev` | Deeper guided feature dev with codebase exploration + architecture options | Larger features that need research first |
| `/design` | Enforces design system rules (colors, spacing, animations) | Before any UI work |
| `/code` | Enforces Swift coding conventions | Before any Swift code |
| `/review` | Reviews code against Cider's standards | After writing code, before committing |
| `/code-review` | Reviews a GitHub PR with parallel agents | Reviewing a pull request |
| `/commit` | Creates a git commit | Ready to commit changes |
| `/commit-push-pr` | Commits, pushes, and opens a PR | Ready to ship a branch |
| `/context` | Dumps project context (what Cider is, tech stack, structure) | New session, need orientation |
| `/clean_gone` | Deletes local branches already removed from remote | Git cleanup |

## End-of-Session Flow

1. **Made design/feature decisions?** Run `/update-vision`
2. **Discovered code patterns or gotchas?** Run `/revise-claude-md`
3. **Wrote code?** Run `/review`, then `/commit`

## Docs Layout

> **See `DOCS_INDEX.md` for the full map** — what every doc covers, what's implemented vs future, and what to update after each session.

```
Docs/
├── DOCS_INDEX.md                 ← start here
├── CODE_HEALTH.md                living bug/debt tracker
│
├── Tab Vision Docs
│   ├── HOME_VISION.md
│   ├── BOOKMARKS_VISION.md
│   ├── NOTES_VISION.md
│   ├── WORKSPACES_VISION.md      folders, projects, saved view tabs
│   ├── AI_VISION.md
│   ├── INTEGRATION_DESIGN.md     Obsidian/knowledge-base sync (→ Docs/Features/)
│   ├── WHITEBOARD_VISION.md      (not yet implemented)
│   ├── DOCUMENTS_VISION.md       (not yet implemented)
│   ├── BOOKS_VISION.md           (not yet implemented)
│   └── TODOS_VISION.md           (not yet implemented)
│
├── Reference Docs (agents read before writing code)
│   ├── DESIGN_SYSTEM.md
│   ├── ACRYLIC_IMPLEMENTATION.md
│   ├── CONVENTIONS.md
│   ├── TECH_STACK.md
│   ├── FLOATING_PANEL.md
│   └── (SHARED_COMPONENTS absorbed into DESIGN_SYSTEM.md §18-19)
│   └── USER_PREFERENCES.md
│
├── Ops
│   ├── RELEASE_CHECKLIST.md
│   ├── TROUBLESHOOTING.md
│   └── NOTES_EDITOR_SMOKE_CHECKLIST.md
│
└── _archive/                     superseded docs, nothing is deleted
```

## Current Tab Status

All tabs are dynamic SavedViews (F-02). Default tabs are Inbox + Library. Users can create, rename, reorder, and close any tab.

| Default Tab | Vision Doc |
|-------------|------------|
| Home | HOME_VISION.md |

| Planned Tab Types | Vision Doc |
|-------------------|------------|
| Whiteboard | WHITEBOARD_VISION.md |
| Documents | DOCUMENTS_VISION.md |
| Books | BOOKS_VISION.md |
| Todos | TODOS_VISION.md |
