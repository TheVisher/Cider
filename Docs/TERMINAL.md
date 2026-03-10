# Terminal (AI Chat Panel)

## Architecture

The AI Chat panel is a floating `AIChatPanel` (NSPanel subclass) with:
- **Header**: SwiftUI `AIChatHeaderView` hosted in an `NSHostingView` — title bar + model selector pills (Shell, Claude, ChatGPT, Codex)
- **Terminal**: Raw AppKit `LocalProcessTerminalView` (SwiftTerm) — NOT inside SwiftUI, added directly as an AppKit subview
- **Background**: `NSVisualEffectView` (.underWindowBackground) + dark tint overlay for acrylic look

The content is assembled in `AIChatContentView` (pure AppKit NSView) which holds both the header hosting view and the terminal as sibling subviews.

### Key Files
| File | Purpose |
|------|---------|
| `App/AIChatPanel.swift` | NSPanel subclass — window setup, dragging, key equivalents |
| `Views/Shared/TerminalView.swift` | `AIChatHeaderView`, `TerminalViewModel`, `AIChatContentView`, `TerminalProcessDelegate` |
| `App/AppDelegate.swift` | Panel lifecycle — `configureAIChatPanel()`, `showAIChatPanel()`, `hideAIChatPanel()` |

## Critical: Keyboard Event Monitor

**CiderPanelView has an app-wide `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` keyboard monitor** that intercepts Enter, Space, Tab, arrows, Delete for card navigation. This monitor fires for ALL key events in the app, including when the terminal is focused.

**The terminal MUST be exempted.** At the top of `handleKeyDown` in CiderPanelView, there's a guard that checks if the first responder is inside a `LocalProcessTerminalView`. If so, it returns the event untouched (passes it through). **Never remove this check** — without it, those keys get consumed for card navigation and the terminal becomes unusable.

```swift
// CiderPanelView.handleKeyDown — MUST be first check
if let responder = NSApp.keyWindow?.firstResponder as? NSView,
   isInsideTerminalView(responder) {
    return event  // Let terminal handle ALL keys
}
```

This was the root cause of a multi-session debugging nightmare. The fix is in CiderPanelView, not in AIChatPanel.

## Terminal Setup

- Shell: user's `$SHELL` (defaults to `/bin/zsh`), launched with `-l` (login shell)
- Working directory: vault directory (`StoragePaths.cachedVaultDirectoryURL`)
- Environment: inherits `PATH` and `HOME` from parent process
- Term type: `xterm-256color`
- Background: dark blue-tinted (`0.07, 0.08, 0.12`) to match acrylic aesthetic
- Model selector can auto-launch CLI tools (e.g. `claude`, `chatgpt`, `codex`) after shell init

## Panel Behavior

- `nonactivatingPanel` — doesn't steal focus from other apps
- `canBecomeKey = true` — can receive key events when clicked
- Floating level, visible on all spaces
- Draggable via header region (top 48pt)
- Positioned next to CiderPanel when visible, otherwise at mouse location
- Height is persisted across show/hide cycles
