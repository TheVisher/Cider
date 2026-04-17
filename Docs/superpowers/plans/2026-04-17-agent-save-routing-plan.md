# Agent Save Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the in-app assistant to route new bookmarks, notes, and contacts using the vault taxonomy before saving, while still falling back to Inbox when routing is unclear.

**Architecture:** Extract the shared vault routing doctrine into one small AI prompt helper, then inject that doctrine into both the Foundation Models and MLX assistant prompts. Add focused tests that verify the routing rules appear in the generated instructions so prompt drift is caught in CI.

**Tech Stack:** Swift, Swift Testing, Foundation Models provider, MLX provider

---

## File Map

- Create: `Sources/Cider/Services/AI/AgentRoutingInstructions.swift`
  - Shared text builder for the vault routing doctrine used by both providers.
- Modify: `Sources/Cider/Services/AI/FoundationModelsProvider.swift`
  - Append shared routing doctrine to the Foundation Models system instructions.
- Modify: `Sources/Cider/Services/AI/MLXProvider.swift`
  - Append shared routing doctrine to the MLX system prompt.
- Create: `Tests/CiderTests/AgentRoutingInstructionsTests.swift`
  - Verifies the shared doctrine text contains the required routing rules.
- Create: `Tests/CiderTests/AIAssistantPromptTests.swift`
  - Verifies both providers include the routing doctrine in their generated prompts.

### Task 1: Add the shared routing doctrine helper

**Files:**
- Create: `Sources/Cider/Services/AI/AgentRoutingInstructions.swift`
- Test: `Tests/CiderTests/AgentRoutingInstructionsTests.swift`

- [ ] **Step 1: Write the failing helper test**

```swift
import Testing
@testable import Cider

struct AgentRoutingInstructionsTests {
    @Test("routing doctrine includes the core vault rules")
    func includesCoreVaultRules() {
        let text = AgentRoutingInstructions.vaultSaveRoutingDoctrine

        #expect(text.contains("Do not invent new top-level folders."))
        #expect(text.contains("Food"))
        #expect(text.contains("People"))
        #expect(text.contains("Inbox"))
        #expect(text.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(text.contains("If the destination is unclear, save to Inbox and explain why."))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AgentRoutingInstructionsTests`

Expected: FAIL with an error similar to `cannot find 'AgentRoutingInstructions' in scope`

- [ ] **Step 3: Add the shared routing doctrine helper**

```swift
import Foundation

enum AgentRoutingInstructions {
    static let vaultSaveRoutingDoctrine = """
    Vault save routing rules:
    - Do not invent new top-level folders.
    - Use the existing vault domains: Inbox, People, Projects, Tech, Food, Hobbies, Life, Media.
    - For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear.
    - For person facts and new contacts, prefer People/{Name}-style routing.
    - Food and recipe content should usually route into Food rather than Inbox.
    - Tech troubleshooting and how-to content should usually route into Tech rather than Inbox.
    - If the destination is unclear, save to Inbox and explain why.
    - In the final response, tell the user where the item was saved.
    """
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AgentRoutingInstructionsTests`

Expected: PASS with `1 test passed`

- [ ] **Step 5: Commit the helper and helper test**

```bash
git add Sources/Cider/Services/AI/AgentRoutingInstructions.swift Tests/CiderTests/AgentRoutingInstructionsTests.swift
git commit -m "Add shared agent routing instructions"
```

### Task 2: Inject the routing doctrine into the Foundation Models prompt

**Files:**
- Modify: `Sources/Cider/Services/AI/FoundationModelsProvider.swift`
- Test: `Tests/CiderTests/AIAssistantPromptTests.swift`

- [ ] **Step 1: Write the failing Foundation prompt test**

```swift
import Testing
@testable import Cider

struct AIAssistantPromptTests {
    @Test("Foundation Models prompt includes vault routing doctrine")
    func foundationPromptIncludesRoutingDoctrine() {
        let provider = FoundationModelsProvider()
        let prompt = provider._buildInstructionsForTesting(context: .init())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter foundationPromptIncludesRoutingDoctrine`

Expected: FAIL because `_buildInstructionsForTesting` does not exist yet

- [ ] **Step 3: Wire the Foundation provider to the shared doctrine**

Update the prompt builder in `Sources/Cider/Services/AI/FoundationModelsProvider.swift` so the routing doctrine is appended after the existing base rules and before any current-view context:

```swift
    private func buildInstructions(context: AIAssistantContext) -> String {
        var instructions = """
        You are a helpful assistant built into Cider, a macOS app for managing \
        bookmarks, notes, events, todos, contacts, and projects.

        Rules:
        - Always use tools to answer questions about the user's data. Never guess.
        - When the user says "this", "this bookmark", "this note", etc., use \
        getCurrentItem to find what they're viewing.
        - For multi-step requests like "find X and move it to Y", use searchItems \
        first, then the appropriate action tool.
        - Be concise. Present tool results clearly without repeating raw data.
        - If a tool returns no results, say so honestly.
        - When creating or modifying items, confirm what you did.
        - Use markdown formatting (bold, lists) for readability.
        """

        instructions += "\n\n\(AgentRoutingInstructions.vaultSaveRoutingDoctrine)"

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            instructions += "\n\nThe user is currently viewing:\n\(contextDesc)"
        }

        return instructions
    }

    nonisolated func _buildInstructionsForTesting(context: AIAssistantContext) -> String {
        buildInstructions(context: context)
    }
```

- [ ] **Step 4: Run the prompt test to verify it passes**

Run: `swift test --filter foundationPromptIncludesRoutingDoctrine`

Expected: PASS

- [ ] **Step 5: Commit the Foundation prompt change**

```bash
git add Sources/Cider/Services/AI/FoundationModelsProvider.swift Tests/CiderTests/AIAssistantPromptTests.swift
git commit -m "Teach Foundation assistant vault save routing"
```

### Task 3: Inject the routing doctrine into the MLX prompt

**Files:**
- Modify: `Sources/Cider/Services/AI/MLXProvider.swift`
- Modify: `Tests/CiderTests/AIAssistantPromptTests.swift`

- [ ] **Step 1: Extend the prompt test with the MLX assertion**

Append this test to `Tests/CiderTests/AIAssistantPromptTests.swift`:

```swift
    @Test("MLX prompt includes vault routing doctrine")
    func mlxPromptIncludesRoutingDoctrine() {
        let provider = MLXProvider(modelManager: MLXModelManager.shared)
        let prompt = provider._buildSystemPromptForTesting(context: .init())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }
```

- [ ] **Step 2: Run the MLX prompt test to verify it fails**

Run: `swift test --filter mlxPromptIncludesRoutingDoctrine`

Expected: FAIL because `_buildSystemPromptForTesting` does not exist yet

- [ ] **Step 3: Wire the MLX provider to the shared doctrine**

Update `Sources/Cider/Services/AI/MLXProvider.swift`:

```swift
    private func buildSystemPrompt(context: AIAssistantContext) -> String {
        var prompt = """
        You are a helpful assistant built into Cider, a macOS app for managing \
        bookmarks, notes, events, todos, contacts, and projects. Be concise, \
        friendly, and accurate. Use markdown formatting for readability.

        # Tools

        You have access to tools to query and modify the user's data. Available tools:
        \(MLXToolDefinitions.allToolsJSON())

        IMPORTANT: When you need to access or modify user data, you MUST call a tool. \
        Output EXACTLY this format (do NOT output anything else before the tool call):
        <tool_call>
        {"name": "toolName", "arguments": {"param": "value"}}
        </tool_call>

        Rules:
        - ALWAYS use tools to get real data. NEVER guess or make up numbers.
        - After receiving a <tool_response>, write a natural response using that data.
        - If the user asks about their items, counts, or data, call the appropriate tool FIRST.
        - Do NOT include raw JSON in your final response to the user.
        """

        prompt += "\n\n\(AgentRoutingInstructions.vaultSaveRoutingDoctrine)"

        let contextDesc = context.contextDescription
        if !contextDesc.isEmpty {
            prompt += "\n\nThe user is currently viewing:\n\(contextDesc)"
        }

        return prompt
    }

    nonisolated func _buildSystemPromptForTesting(context: AIAssistantContext) -> String {
        buildSystemPrompt(context: context)
    }
```

- [ ] **Step 4: Run the MLX prompt test to verify it passes**

Run: `swift test --filter mlxPromptIncludesRoutingDoctrine`

Expected: PASS

- [ ] **Step 5: Commit the MLX prompt change**

```bash
git add Sources/Cider/Services/AI/MLXProvider.swift Tests/CiderTests/AIAssistantPromptTests.swift
git commit -m "Teach MLX assistant vault save routing"
```

### Task 4: Run the focused verification pass

**Files:**
- Modify: none
- Test: `Tests/CiderTests/AgentRoutingInstructionsTests.swift`
- Test: `Tests/CiderTests/AIAssistantPromptTests.swift`

- [ ] **Step 1: Run the focused prompt test suite**

Run: `swift test --filter "(AgentRoutingInstructionsTests|AIAssistantPromptTests)"`

Expected: PASS with all routing prompt tests green

- [ ] **Step 2: Run the existing safety regression suite**

Run: `swift test --filter "(DailyVaultReminderServiceTests|MutationAuditServiceTests|TrashSQLiteTests|CiderDatabaseTests)"`

Expected: PASS with no regressions in the recent reminder/audit/database work

- [ ] **Step 3: Inspect the working tree**

Run: `git status --short`

Expected: no unexpected modified files

- [ ] **Step 4: Commit the verification checkpoint if needed**

```bash
git add Tests/CiderTests/AgentRoutingInstructionsTests.swift Tests/CiderTests/AIAssistantPromptTests.swift
git commit -m "Add routing prompt coverage"
```

## Self-Review

### Spec coverage

- Prompt-only routing experiment: covered by Tasks 1-3
- Bookmarks, notes, contacts scope: covered through doctrine text in Task 1
- Inbox fallback on uncertainty: covered through doctrine text and prompt tests
- Both providers updated: covered by Tasks 2-3
- Manual follow-up behavior testing: intentionally left for post-implementation product validation, consistent with the spec

### Placeholder scan

- No `TODO`, `TBD`, or deferred implementation placeholders remain
- Every code-changing step includes exact file paths, code, and commands

### Type consistency

- Shared helper symbol: `AgentRoutingInstructions.vaultSaveRoutingDoctrine`
- Foundation test shim: `_buildInstructionsForTesting(context:)`
- MLX test shim: `_buildSystemPromptForTesting(context:)`

