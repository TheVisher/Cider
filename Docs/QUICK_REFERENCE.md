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

```
Docs/
├── Tab Vision Docs (feature plans per tab)
│   ├── HOME_VISION.md
│   ├── BOOKMARKS_VISION.md
│   ├── NOTES_VISION.md
│   ├── WHITEBOARD_VISION.md      (not yet implemented)
│   ├── DOCUMENTS_VISION.md       (not yet implemented)
│   ├── BOOKS_VISION.md           (not yet implemented)
│   └── TODOS_VISION.md           (not yet implemented)
│
├── System Docs (how to build things)
│   ├── DESIGN_SYSTEM.md          colors, typography, spacing tokens
│   ├── ACRYLIC_STYLE.md          material/shadow patterns
│   ├── CONVENTIONS.md            Swift style guide
│   ├── TECH_STACK.md             Swift 6.2, concurrency, storage
│   ├── FLOATING_PANEL.md         NSPanel architecture
│   ├── SHARED_COMPONENTS.md      reusable cross-tab components
│   └── USER_PREFERENCES.md      settings/CiderConfig patterns
│
├── Feature Docs
│   ├── WORKSPACES_VISION.md      folders, projects, search
│   ├── WORKSPACES_IMPLEMENTATION_PLAN.md
│   ├── UX_FOLDER_DESIGN.md
│   └── UX_TAB_SIMPLIFICATION.md  (future proposal, not approved)
│
├── Ops
│   ├── RELEASE_CHECKLIST.md
│   ├── TROUBLESHOOTING.md
│   └── NOTES_EDITOR_SMOKE_CHECKLIST.md
│
└── _archive/                     old/superseded docs
```

## Current Tab Status

| Tab | Status | Vision Doc |
|-----|--------|------------|
| Home | Live | HOME_VISION.md |
| Bookmarks | Live | BOOKMARKS_VISION.md |
| Notes | Live | NOTES_VISION.md |
| Whiteboard | Planned | WHITEBOARD_VISION.md |
| Documents | Planned | DOCUMENTS_VISION.md |
| Books | Planned | BOOKS_VISION.md |
| Todos | Planned | TODOS_VISION.md |
