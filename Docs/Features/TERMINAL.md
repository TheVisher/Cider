# AI Chat Panel

> **DEPRECATED:** This document describes the old CLI-process-based AI chat architecture that was fully replaced by the AI Assistant system. None of the files listed below exist in the codebase. See `Docs/Features/AI.md` for the current AI architecture (Foundation Models + MLX Swift with tool calling).

The old architecture piped user messages to CLI tools (Claude, ChatGPT, Codex) via `Foundation.Process` stdin/stdout. It was replaced because:

1. CLI tools required users to have separate accounts and API keys
2. The local-first philosophy (zero-cost, no cloud APIs) made on-device models preferable
3. The Foundation Models framework (macOS 26+) and MLX Swift provide better integration

### Current AI System

The AI chat is now the **AI Assistant** — a floating NSPanel with two backends:

- **Apple Intelligence** (Foundation Models, 4K context, 23 tools)
- **Local Model** (Qwen 2.5 via MLX Swift, 32K context, 23 tools via prompt-based calling)

Key files: `Services/AI/AIAssistantProvider.swift`, `Services/AI/FoundationModelsProvider.swift`, `Services/AI/MLXProvider.swift`, `Services/AI/MLXToolExecutor.swift`, `ViewModels/AIAssistantViewModel.swift`, `Views/AIAssistant/AIAssistantPanelView.swift`.

See `Docs/Features/AI.md` for full documentation.
