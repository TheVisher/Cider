# AI Chat Panel

## Architecture

The AI Chat is a native SwiftUI chat bubble interface that runs CLI tools (Claude, ChatGPT, Codex) as background processes. User messages are piped to stdin, CLI output streams back as chat bubbles.

### Why Not a Terminal?

The original implementation used SwiftTerm (terminal emulator). This caused key handling nightmares — CiderPanelView's app-wide keyboard monitor intercepted Enter, Space, Tab, arrows for card navigation, making the terminal unusable. The native chat UI avoids this entirely since SwiftUI TextFields handle their own key events through the normal responder chain.

### Key Files

| File | Purpose |
|------|---------|
| `Models/AIChatMessage.swift` | Chat message model (role, content, streaming state) |
| `Models/AIModelOption.swift` | Model definitions (Shell, Claude, ChatGPT, Codex) |
| `Services/AI/AIChatProcessService.swift` | Manages CLI Process — stdin/stdout pipes, ANSI stripping |
| `ViewModels/AIChatViewModel.swift` | Message list, process lifecycle, model selection |
| `Views/AIChat/AIChatView.swift` | Top-level view — header + messages + input |
| `Views/AIChat/AIChatBubbleView.swift` | Individual message bubble (user/assistant/system) |
| `Views/AIChat/AIChatInputView.swift` | Text input field with send button |
| `App/AIChatPanel.swift` | NSPanel subclass for floating mode |
| `App/AppDelegate.swift` | Panel lifecycle, dock/undock orchestration |

## Dock / Undock

The AI Chat works in two modes — both observe the **same** `AIChatViewModel`:

- **Floating:** Pure SwiftUI `AIChatView` hosted in `NSHostingView` inside `AIChatPanel`
- **Docked:** Same `AIChatView` rendered directly in CiderPanelView's tab content

Switching modes is trivial — just hide/show the floating panel and select/deselect the `.aiChat` tab. No view reparenting needed. The shared view model preserves conversation state across mode switches.

## Process Management

- CLI tools are launched via `Foundation.Process` with stdin/stdout pipes
- `TERM=dumb` and `NO_COLOR=1` are set to suppress terminal formatting
- Output is stripped of ANSI escape codes before display
- After 1 second of idle output, the current response is marked as complete
- The process runs in the vault directory (`StoragePaths.cachedVaultDirectoryURL`)

## Keyboard Event Monitor

CiderPanelView has an app-wide keyboard monitor for card navigation. When the `.aiChat` tab is active, the handler short-circuits and passes all events through to the chat input field. This is checked via `isInsideAIChatView()` at the top of `handleKeyDown`.

## Panel Behavior

- `nonactivatingPanel` — doesn't steal focus from other apps
- `canBecomeKey = true` — receives key events when clicked
- Floating level, visible on all spaces
- Draggable via header region (top 48pt)
- Height persisted across show/hide cycles
