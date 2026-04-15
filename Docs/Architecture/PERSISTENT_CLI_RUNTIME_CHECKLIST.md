# Persistent CLI Runtime Checklist

## Goal

Make the existing Cider AI chat panel capable of talking to a long-lived background CLI agent while preserving the current model-backed path.

The chat UI already works for:

- MLX / Qwen
- Foundation Models / Apple Intelligence

This checklist adds:

- a persistent process-backed runtime family
- lifecycle management for a vault agent
- enough UI/runtime wiring to use the existing chat panel as the interface

The first target runtime is a Codex-backed CLI runtime. The same architecture should later support Gemini CLI and similar subscription-backed tools.

---

## Design Constraints

- Do not replace the current AI panel.
- Do not fork a separate conversation UI.
- Keep `AgentOrchestrator` as the single routing layer.
- Preserve current `ModelAgentRuntime` behavior.
- Add `ProcessAgentRuntime` as a peer runtime family.
- Design around one long-lived agent process per vault while Cider is open.
- Plan for future agent rotation:
  - restart
  - stop
  - spawn fresh
  - promote fresh

---

## Phase 1: Runtime Foundation

### 1. Extend the runtime model

- [ ] Confirm `AgentRuntime` is sufficient for both model-backed and process-backed runtimes.
- [ ] Add process-health/lifecycle structures if needed:
  - [ ] `AgentRuntimeHealth`
  - [ ] `AgentRuntimeStatus`
  - [ ] `AgentRuntimeMetadata`
- [ ] Add optional lifecycle methods if needed:
  - [ ] `start()`
  - [ ] `stop()`
  - [ ] `restart()`
  - [ ] `health()`

### 2. Add `ProcessAgentRuntime`

- [ ] Create a new process runtime protocol or base type.
- [ ] Define the minimum contract:
  - [ ] launch path / command
  - [ ] working directory
  - [ ] start/stop/restart
  - [ ] health/state reporting
  - [ ] send/stream integration
- [ ] Keep this parallel to `ModelAgentRuntime`, not mixed into it.

### 3. Add `AgentProcessManager`

- [ ] Create a manager responsible for process lifecycle.
- [ ] Track:
  - [ ] process handle
  - [ ] runtime status
  - [ ] launch/start time
  - [ ] last activity time
  - [ ] restart attempts
  - [ ] last error
- [ ] Support:
  - [ ] start
  - [ ] stop
  - [ ] restart
  - [ ] auto-restart backoff
  - [ ] graceful shutdown on app quit

### 4. Add initial `CodexProcessRuntime`

- [ ] Create a concrete runtime class for Codex CLI.
- [ ] Start with lifecycle skeleton first.
- [ ] Do not over-design transport before the process plumbing is in place.
- [ ] Ensure the runtime knows:
  - [ ] vault/repo working directory
  - [ ] launch command
  - [ ] environment it needs
- [ ] Return clear placeholder errors for unsupported send/stream behavior until transport is wired.

---

## Phase 2: Existing Chat Window Integration

### 5. Use the current AI panel as the interface

- [ ] Keep `AIAssistantViewModel` as the panel-facing layer.
- [ ] Continue routing through `AgentOrchestrator`.
- [ ] Make orchestrator able to target either:
  - [ ] `ModelAgentRuntime`
  - [ ] `ProcessAgentRuntime`

### 6. Add runtime selection/status to the current chat path

- [ ] Add a concept of active runtime in the existing AI layer.
- [ ] Surface runtime name in the current panel/view model.
- [ ] Surface runtime status:
  - [ ] running
  - [ ] starting
  - [ ] restarting
  - [ ] stopped
  - [ ] failed
- [ ] Keep current model switching working.
- [ ] Do not break MLX/FoundationModels fallback.

### 7. Compile with both runtime families present

- [ ] Existing panel path should still work with current models.
- [ ] New runtime foundation should compile even if Codex transport is not complete yet.
- [ ] Orchestrator should not assume all runtimes are model-backed.

---

## Phase 3: Persistent Agent Lifecycle Controls

### 8. Add explicit lifecycle operations

- [ ] `Restart Agent`
- [ ] `Stop Agent`
- [ ] `Spawn Fresh Agent`
- [ ] `Promote Fresh Agent`

### 9. Define active vs fresh process model

- [ ] One active runtime process
- [ ] Optional fresh candidate runtime
- [ ] Handoff summary hook for rotation
- [ ] Promote/swap semantics

---

## Phase 4: Durable Vault Memory

### 10. Add vault-backed long-term memory

- [ ] Define what gets saved durably:
  - [ ] user preferences
  - [ ] recurring commitments
  - [ ] important decisions
  - [ ] project summaries
  - [ ] reminder-relevant facts
  - [ ] open loops/follow-ups
- [ ] Keep this separate from raw live process context.
- [ ] Make it inspectable and editable in the vault.

### 11. Support agent rotation without losing the relationship

- [ ] Fresh agent can boot from vault memory
- [ ] Active process context can be summarized before rotation
- [ ] Memory should prevent “indefinite context compaction agent” drift

---

## Phase 5: Remote Channel Management

### 12. Connect Telegram to the same active agent

- [ ] Telegram should route through `AgentOrchestrator`
- [ ] Telegram should talk to the same logical thread as the AI panel when appropriate
- [ ] Reminder delivery should route through the same runtime

### 13. Add simple remote admin commands

- [ ] `/status`
- [ ] `/runtime`
- [ ] `/restart`
- [ ] `/fresh`
- [ ] `/memory`

---

## Immediate Coding Slice

The highest-value next implementation slice is:

1. [ ] Add `ProcessAgentRuntime`
2. [ ] Add `AgentProcessManager`
3. [ ] Add `CodexProcessRuntime` lifecycle skeleton
4. [ ] Make the existing AI panel/runtime path aware of process runtimes
5. [ ] Show runtime status/name in the current AI panel path
6. [ ] Keep current model-backed path working

This is intentionally narrow. It gets the foundation in place without forcing transport, memory, and remote lifecycle work into one diff.

---

## Acceptance Criteria For Phase 1

- [ ] Project compiles
- [ ] Existing AI panel still works with MLX/FoundationModels
- [ ] A process runtime can be selected/set in code
- [ ] Process manager can start and stop a background runtime process
- [ ] Runtime status is visible from the current AI layer
- [ ] App can shut down the managed process cleanly
- [ ] No channel layer is hard-coupled to a specific LLM

---

## Follow-Up After Phase 1

Once Phase 1 is stable, the next work item should be:

- structured transport for the selected CLI runtime

Only after that should the implementation move on to:

- fresh-agent rotation
- durable vault memory
- Telegram runtime management commands

