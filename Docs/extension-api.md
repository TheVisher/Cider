# Sidebar Extension API (Legacy)

> **Legacy note:** This spec describes a sidebar-era extension system that is not implemented in the current command‑palette product. Treat this as archival reference until a palette extension model is defined.

## Overview

The Sidebar app supports user-created extensions that add new floating components to the sidebar. Extensions are self-contained modules that can display information, accept interactions, and integrate with system APIs.

## Extension Interface

```swift
protocol SidebarExtension {
    /// Unique identifier for the extension
    var id: String { get }
    
    /// Display name shown in extension manager
    var name: String { get }
    
    /// SF Symbol or emoji for the icon
    var icon: String { get }
    
    /// Render the extension's UI
    func render(context: ExtensionContext) -> some View
    
    /// Called when user hovers over the extension (optional)
    func onHover() -> Void
    
    /// Called when user stops hovering (optional)
    func onHoverEnd() -> Void
    
    /// Handle files dropped onto this extension (optional)
    func onFileDrop(files: [URL]) -> Void
    
    /// Handle items dragged out of this extension (optional)
    func onDragOut() -> [NSItemProvider]?
    
    /// Settings/preferences view (optional)
    func settingsView() -> some View
}
```

## Extension Context

Extensions receive a context object that provides access to system capabilities:

```swift
struct ExtensionContext {
    /// Current hover state (contracted, normal, expanded)
    let displayState: DisplayState
    
    /// Available height for the extension
    let availableHeight: CGFloat
    
    /// Access to the clipboard
    let clipboard: ClipboardService
    
    /// Access to staged files in the drop zone
    let dropZone: DropZoneService
    
    /// Access to window information
    let windowManager: WindowManagerService
    
    /// Persistent storage for this extension
    let storage: ExtensionStorage
    
    /// Network requests (sandboxed)
    let network: NetworkService
    
    /// System notifications
    let notifications: NotificationService
}

enum DisplayState {
    case contracted  // Other extension is hovered
    case normal      // Default state
    case expanded    // This extension is hovered
}
```

## Available Services

### ClipboardService
```swift
protocol ClipboardService {
    /// Current clipboard contents
    var current: ClipboardItem? { get }
    
    /// Recent clipboard history
    var history: [ClipboardItem] { get }
    
    /// Copy item to clipboard
    func copy(_ item: ClipboardItem)
    
    /// Listen for clipboard changes
    func onChange(_ handler: @escaping (ClipboardItem) -> Void)
}
```

### DropZoneService
```swift
protocol DropZoneService {
    /// Currently staged files
    var stagedFiles: [URL] { get }
    
    /// Add files to staging area
    func stage(files: [URL])
    
    /// Remove file from staging
    func unstage(file: URL)
    
    /// Clear all staged files
    func clearAll()
}
```

### WindowManagerService
```swift
protocol WindowManagerService {
    /// All open windows
    var windows: [WindowInfo] { get }
    
    /// Windows grouped by application
    var windowsByApp: [AppInfo: [WindowInfo]] { get }
    
    /// Focus a specific window
    func focus(window: WindowInfo)
    
    /// Minimize a window
    func minimize(window: WindowInfo)
    
    /// Close a window
    func close(window: WindowInfo)
    
    /// Create a window group
    func group(windows: [WindowInfo]) -> WindowGroup
    
    /// Tile windows
    func tile(windows: [WindowInfo], layout: TileLayout)
}
```

### ExtensionStorage
```swift
protocol ExtensionStorage {
    /// Get value for key
    func get<T: Codable>(_ key: String) -> T?
    
    /// Set value for key
    func set<T: Codable>(_ key: String, value: T)
    
    /// Remove value
    func remove(_ key: String)
    
    /// All keys
    var keys: [String] { get }
}
```

## Example Extension: Pomodoro Timer

```swift
import SidebarKit

struct PomodoroExtension: SidebarExtension {
    let id = "com.example.pomodoro"
    let name = "Pomodoro Timer"
    let icon = "🍅"
    
    @State private var timeRemaining: Int = 25 * 60
    @State private var isRunning: Bool = false
    @State private var isBreak: Bool = false
    
    func render(context: ExtensionContext) -> some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("POMODORO")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            
            // Timer display
            Text(formatTime(timeRemaining))
                .font(.system(size: context.displayState == .expanded ? 32 : 20, weight: .light))
                .foregroundColor(.white)
            
            // Controls (only when expanded)
            if context.displayState == .expanded {
                HStack(spacing: 16) {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    Button(action: toggleTimer) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    }
                    Button(action: skip) {
                        Image(systemName: "forward.fill")
                    }
                }
                .foregroundColor(.white.opacity(0.8))
                
                // Session info
                Text(isBreak ? "Break Time" : "Focus Session")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(8)
    }
    
    func settingsView() -> some View {
        Form {
            Stepper("Focus Duration: \(focusDuration) min", value: $focusDuration, in: 5...60)
            Stepper("Break Duration: \(breakDuration) min", value: $breakDuration, in: 1...30)
            Toggle("Sound Notifications", isOn: $soundEnabled)
            Toggle("Desktop Notifications", isOn: $notificationsEnabled)
        }
    }
}
```

## Example Extension: Git Status

```swift
import SidebarKit

struct GitStatusExtension: SidebarExtension {
    let id = "com.example.gitstatus"
    let name = "Git Status"
    let icon = "📊"
    
    @State private var repos: [RepoStatus] = []
    
    func render(context: ExtensionContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GIT STATUS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white.opacity(0.4))
            }
            
            ForEach(repos) { repo in
                RepoRow(repo: repo, expanded: context.displayState == .expanded)
            }
        }
        .padding(8)
        .onAppear { refresh() }
    }
    
    struct RepoRow: View {
        let repo: RepoStatus
        let expanded: Bool
        
        var body: some View {
            HStack {
                Circle()
                    .fill(repo.hasChanges ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                
                Text(repo.name)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                if expanded {
                    Text(repo.branch)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if repo.hasChanges {
                        Text("+\(repo.additions) -\(repo.deletions)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}
```

## Extension Distribution

Extensions can be distributed via:

1. **Built-in Extensions** - Ship with the app, toggleable in settings
2. **Extension Gallery** - Curated marketplace (future)
3. **Manual Install** - Load from `.sidebarext` bundle
4. **Developer Mode** - Load from source during development

## Security Model

Extensions run in a sandboxed environment with limited capabilities:

- ✅ Read window list and metadata
- ✅ Access clipboard (with permission)
- ✅ Receive dropped files
- ✅ Make network requests to allowlisted domains
- ✅ Store persistent data (limited quota)
- ✅ Send notifications
- ❌ Access filesystem outside drops
- ❌ Execute shell commands
- ❌ Modify other extensions
- ❌ Access keychain
- ❌ Screen recording/capture

## Packaging

Extensions are packaged as `.sidebarext` bundles:

```
MyExtension.sidebarext/
├── manifest.json
├── Extension.swift (compiled)
├── Assets/
│   ├── icon.png
│   └── icon@2x.png
├── Localizations/
│   ├── en.lproj/
│   └── es.lproj/
└── README.md
```

### manifest.json

```json
{
  "id": "com.developer.myextension",
  "name": "My Extension",
  "version": "1.0.0",
  "minSidebarVersion": "1.0",
  "author": "Developer Name",
  "description": "Does something useful",
  "icon": "icon.png",
  "permissions": [
    "clipboard.read",
    "clipboard.write",
    "notifications",
    "network:api.example.com"
  ],
  "settings": true
}
```

## Development Workflow

1. Create extension using Xcode template or CLI:
   ```bash
   sidebar create-extension MyExtension
   ```

2. Develop with hot reload:
   ```bash
   sidebar dev MyExtension/
   ```

3. Test in sandbox:
   ```bash
   sidebar test MyExtension/
   ```

4. Package for distribution:
   ```bash
   sidebar package MyExtension/
   ```

5. Submit to gallery (optional):
   ```bash
   sidebar publish MyExtension.sidebarext
   ```
