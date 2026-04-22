# Staged Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the five review findings in a controlled sequence: restore clean builds, enforce AI tool permissions, harden AI conversation persistence, remove URL-order-dependent bookmark scan behavior, and reduce legacy review/tooling debt.

**Architecture:** Work in narrow vertical slices. Each slice starts with a focused reproduction or failing test, implements the minimal fix, then re-runs targeted verification before the next slice begins. Avoid cross-cutting refactors unless a step explicitly calls for them.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI/AppKit, FoundationModels, XCTest.

---

## File Map

- Modify: `Sources/Cider/Utilities/CiderDragPayload.swift`
- Modify: `Sources/Cider/Services/Agent/FoundationModelsAgentProvider.swift`
- Modify: `Sources/Cider/Services/Agent/AgentOrchestrator.swift` if permission plumbing needs adjustment
- Modify: `Sources/Cider/Services/AI/AIConversationStorage.swift`
- Modify: `Sources/Cider/Services/VaultBookmarkService.swift`
- Modify: `Docs/Conventions/CODE_HEALTH.md`
- Search/remove if present: CodeRabbit-related repo files or references
- Add tests where practical in `Tests/CiderTests/`

### Task 1: Restore Clean Build for Drag Payload Registration

**Files:**
- Modify: `Sources/Cider/Utilities/CiderDragPayload.swift`
- Verify: package build

- [ ] **Step 1: Reproduce the current failure**

Run: `swift build -Xswiftc -warnings-as-errors`
Expected: FAIL with `ActorIsolatedCall` errors pointing at `CiderDragPayload.swift`.

- [ ] **Step 2: Inspect each registration helper**

Confirm which helpers are marked `@MainActor` and which `registerDataRepresentation` closures are triggering the compiler error:
- `BookmarkDragPayload.registerPublicURL`
- `BookmarkDragPayload.registerPublicImage`
- `NoteDragPayload.registerPublicFileURL`
- `CiderMultiDrag.makeProvider`

- [ ] **Step 3: Implement the minimal isolation fix**

Adjust the drag payload helpers so they do not invoke provider completion handlers from a main-actor-isolated synchronous context. Keep existing drag behavior unchanged.

- [ ] **Step 4: Re-run the build**

Run: `swift build -Xswiftc -warnings-as-errors`
Expected: no `CiderDragPayload.swift` actor-isolation errors.

- [ ] **Step 5: Commit checkpoint**

Commit message: `fix: restore drag payload build compatibility`

### Task 2: Enforce Tool Permissions for Apple Intelligence

**Files:**
- Modify: `Sources/Cider/Services/Agent/FoundationModelsAgentProvider.swift`
- Modify: `Sources/Cider/Services/Agent/AgentOrchestrator.swift` only if needed
- Add or modify tests in `Tests/CiderTests/` if a focused unit test is feasible

- [ ] **Step 1: Reproduce and pin down the permission gap**

Verify from code that the provider receives a filtered `tools` list from the orchestrator but still binds a hard-coded full `LanguageModelSession` tool array.

- [ ] **Step 2: Decide the narrowest safe fix**

Preferred direction:
- derive the Foundation Models session tool list from the incoming `toolDefinitions`
- avoid broad refactors of the runtime/orchestrator shape in this pass

- [ ] **Step 3: Add a focused regression test if feasible**

Candidate test behavior:
- when only a limited tool subset is allowed, the provider/session setup should not expose `deleteItem`

If `LanguageModelSession` is not directly testable in unit tests, document that and verify through code-level assertions plus targeted build/test coverage around helper mapping logic.

- [ ] **Step 4: Implement the fix**

Make `FoundationModelsAgentProvider` honor the tool list passed into `generate` / `streamGenerate` instead of always using the full hard-coded list.

- [ ] **Step 5: Run targeted verification**

Run the smallest test command that exercises the new mapping logic.
If no unit test is possible, run `swift build -Xswiftc -warnings-as-errors` and document the limitation.

- [ ] **Step 6: Commit checkpoint**

Commit message: `fix: respect agent tool permissions for foundation models`

### Task 3: Harden AI Conversation Persistence

**Files:**
- Modify: `Sources/Cider/Services/AI/AIConversationStorage.swift`
- Add tests: `Tests/CiderTests/AIConversationStorageTests.swift` if absent

- [ ] **Step 1: Write the failing persistence tests**

Cover at least:
- saving the same conversation twice preserves original `created`
- renaming/resaving does not lose the conversation
- save flow does not depend on deleting the old file first

- [ ] **Step 2: Run the test file to verify failure**

Run: `swift test --filter AIConversationStorageTests`
Expected: FAIL on current persistence behavior, or fail because tests do not yet compile against missing seams.

- [ ] **Step 3: Implement the minimal storage fix**

Change `AIConversationStorage.save` so it:
- loads existing metadata when the conversation already exists
- preserves original `created`
- writes replacement content safely before removing obsolete filename variants
- keeps `conversations` refreshed after save

- [ ] **Step 4: Re-run the targeted tests**

Run: `swift test --filter AIConversationStorageTests`
Expected: PASS.

- [ ] **Step 5: Commit checkpoint**

Commit message: `fix: harden ai conversation persistence`

### Task 4: Remove URL-Order-Dependent Bookmark Scan Behavior

**Files:**
- Modify: `Sources/Cider/Services/VaultBookmarkService.swift`
- Add/extend tests near bookmark scanning behavior in `Tests/CiderTests/`

- [ ] **Step 1: Write a failing test for duplicate URL handling**

Cover a case where the same URL exists in two folders and verify the chosen behavior is stable and intentional rather than scan-order-dependent.

- [ ] **Step 2: Run the targeted test to verify failure**

Run the narrowest bookmark scan test command.
Expected: FAIL against current `seenURLs` behavior or reveal the missing test seam to create.

- [ ] **Step 3: Implement the chosen stable policy**

Keep the fix narrow. Acceptable outcomes include:
- preserving both bookmark records if identity differs, or
- choosing a deterministic winner with explicit precedence plus documentation

Do not slip into a full bookmark model redesign in this pass.

- [ ] **Step 4: Re-run targeted verification**

Run the bookmark scan test file or focused filter.
Expected: PASS.

- [ ] **Step 5: Commit checkpoint**

Commit message: `fix: stabilize duplicate bookmark scan behavior`

### Task 5: Clean Up Legacy Debt and Stale Review Artifacts

**Files:**
- Modify: `Docs/Conventions/CODE_HEALTH.md`
- Search/remove stale external review-tool references in repo config/docs if present
- Narrow legacy bookmark/runtime debt only where it is clearly unused or misleading

- [ ] **Step 1: Search for CodeRabbit references and stale health notes**

Look for:
- stale review-tool references in docs/config
- stale `CH-C23` wording in `CODE_HEALTH.md`

- [ ] **Step 2: Remove or update the non-code debt**

Do the smallest safe cleanup:
- remove CodeRabbit-specific repo references the user no longer wants
- update `CH-C23` if the bug is already fixed in code

- [ ] **Step 3: Evaluate legacy bookmark service cleanup scope**

Only make code changes here if they are clearly isolated and low-risk.
If collapsing `BookmarksStorage` is bigger than this pass, capture that as a follow-up note instead of forcing a risky refactor.

- [ ] **Step 4: Run final verification for touched areas**

Run:
- `swift build -Xswiftc -warnings-as-errors`
- relevant targeted `swift test --filter ...` commands from Tasks 2-4

Expected: build succeeds and all targeted tests pass.

- [ ] **Step 5: Commit checkpoint**

Commit message: `chore: remove stale review artifacts`

## Final Verification

- [ ] Run `swift build -Xswiftc -warnings-as-errors`
- [ ] Run all targeted test commands added during Tasks 2-4
- [ ] Review `git diff --stat` for unintended spillover
- [ ] Summarize remaining follow-up work separately from completed fixes
