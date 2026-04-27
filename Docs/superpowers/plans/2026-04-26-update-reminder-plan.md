# Update Reminder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hideable sidebar reminder for available Sparkle updates, with an expanded `Update Available` row, a collapsed badge, and a Settings toggle.

**Architecture:** Keep Sparkle as the source of update discovery in `SparkleUpdaterService`, but extract reminder visibility rules into a tiny pure Swift model so the behavior is easy to test without constructing Sparkle. The sidebar observes `SparkleUpdaterService.shared`; Settings writes the same service preference, so both surfaces stay in sync.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Sparkle `SPUStandardUpdaterController`, `SPUUpdaterDelegate`, XCTest.

---

## File Structure

- Create `Sources/Cider/Services/SparkleUpdateReminderState.swift`
  - Pure value type for update reminder visibility rules.
  - No Sparkle imports, no `UserDefaults`, no UI.
- Modify `Sources/Cider/Services/SparkleUpdaterService.swift`
  - Adopt `SPUUpdaterDelegate`.
  - Publish available update state.
  - Persist sidebar reminder preference and dismissed update identifier.
  - Forward Sparkle update-found and no-update callbacks into the reminder state.
- Modify `Sources/Cider/Views/Settings/SettingsView.swift`
  - Add local state binding for the new sidebar reminder toggle.
- Modify `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift`
  - Render `Show update reminders in sidebar` under `Settings > General > Startup > Updates`.
- Modify `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`
  - Observe updater state in `SidebarProfilePanel`.
  - Render expanded update row, collapsed badge, and dismiss affordance.
  - Respect `reduceMotion` for the pulse.
- Create `Tests/CiderTests/SparkleUpdateReminderStateTests.swift`
  - Unit tests for visibility and dismissal rules.

## Task 1: Add Pure Reminder State

**Files:**
- Create: `Sources/Cider/Services/SparkleUpdateReminderState.swift`
- Test: `Tests/CiderTests/SparkleUpdateReminderStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CiderTests/SparkleUpdateReminderStateTests.swift`:

```swift
import XCTest
@testable import Cider

final class SparkleUpdateReminderStateTests: XCTestCase {
    func testReminderVisibleWhenUpdateAvailableEnabledAndNotDismissed() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertTrue(state.shouldShowSidebarReminder)
    }

    func testReminderHiddenWhenSidebarRemindersDisabled() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: false,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }

    func testReminderHiddenAfterDismissingCurrentUpdate() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.1-10",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "0.1.1-10"
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }

    func testReminderVisibleAgainForDifferentUpdateIdentifier() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: "0.1.2-11",
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: "0.1.1-10"
        )

        XCTAssertTrue(state.shouldShowSidebarReminder)
    }

    func testReminderHiddenWhenNoUpdateIsAvailable() {
        let state = SparkleUpdateReminderState(
            availableUpdateIdentifier: nil,
            sidebarRemindersEnabled: true,
            dismissedUpdateIdentifier: nil
        )

        XCTAssertFalse(state.shouldShowSidebarReminder)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter SparkleUpdateReminderStateTests
```

Expected: FAIL because `SparkleUpdateReminderState` does not exist.

- [ ] **Step 3: Add the pure model**

Create `Sources/Cider/Services/SparkleUpdateReminderState.swift`:

```swift
import Foundation

struct SparkleUpdateReminderState: Equatable {
    var availableUpdateIdentifier: String?
    var sidebarRemindersEnabled: Bool
    var dismissedUpdateIdentifier: String?

    var shouldShowSidebarReminder: Bool {
        guard sidebarRemindersEnabled,
              let availableUpdateIdentifier,
              availableUpdateIdentifier.isEmpty == false else {
            return false
        }
        return availableUpdateIdentifier != dismissedUpdateIdentifier
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter SparkleUpdateReminderStateTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Services/SparkleUpdateReminderState.swift Tests/CiderTests/SparkleUpdateReminderStateTests.swift
git commit -m "Add Sparkle update reminder state"
```

## Task 2: Publish Update Reminder State From SparkleUpdaterService

**Files:**
- Modify: `Sources/Cider/Services/SparkleUpdaterService.swift`
- Test: `Tests/CiderTests/SparkleUpdateReminderStateTests.swift`

- [ ] **Step 1: Add service-facing expectations to the pure state tests**

Append this test to `Tests/CiderTests/SparkleUpdateReminderStateTests.swift`:

```swift
func testReminderStateUsesPersistedDismissalForExactIdentifierOnly() {
    let dismissedCurrent = SparkleUpdateReminderState(
        availableUpdateIdentifier: "1.0.0-100",
        sidebarRemindersEnabled: true,
        dismissedUpdateIdentifier: "1.0.0-100"
    )
    let nextUpdate = SparkleUpdateReminderState(
        availableUpdateIdentifier: "1.0.1-101",
        sidebarRemindersEnabled: true,
        dismissedUpdateIdentifier: "1.0.0-100"
    )

    XCTAssertFalse(dismissedCurrent.shouldShowSidebarReminder)
    XCTAssertTrue(nextUpdate.shouldShowSidebarReminder)
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
swift test --filter SparkleUpdateReminderStateTests
```

Expected: PASS. This locks the dismissal semantics before wiring the service.

- [ ] **Step 3: Update the service properties and initializer**

In `Sources/Cider/Services/SparkleUpdaterService.swift`, replace the stored-property block and `override init()` with this shape, preserving the existing `updaterController`, `userDriverDelegate`, and window-demotion behavior:

```swift
@MainActor
final class SparkleUpdaterService: NSObject, ObservableObject {
    static let shared = SparkleUpdaterService()

    private enum DefaultsKey {
        static let showSidebarUpdateReminders = "cider.showSidebarUpdateReminders"
        static let dismissedSidebarUpdateIdentifier = "cider.dismissedSidebarUpdateIdentifier"
    }

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = SparkleUpdaterDelegate()
    private let userDriverDelegate = SparkleUserDriverDelegate()
    private let defaults: UserDefaults
    private var temporarilyDemotedWindows: [(window: NSWindow, level: NSWindow.Level)] = []

    @Published private(set) var availableUpdateIdentifier: String?
    @Published private(set) var availableUpdateDisplayVersion: String?
    @Published private var dismissedSidebarUpdateIdentifier: String?
    @Published var showSidebarUpdateReminders: Bool {
        didSet {
            defaults.set(showSidebarUpdateReminders, forKey: DefaultsKey.showSidebarUpdateReminders)
        }
    }

    var shouldShowSidebarUpdateReminder: Bool {
        SparkleUpdateReminderState(
            availableUpdateIdentifier: availableUpdateIdentifier,
            sidebarRemindersEnabled: showSidebarUpdateReminders,
            dismissedUpdateIdentifier: dismissedSidebarUpdateIdentifier
        ).shouldShowSidebarReminder
    }

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let hasReminderPreference = defaults.object(forKey: DefaultsKey.showSidebarUpdateReminders) != nil
        self.showSidebarUpdateReminders = hasReminderPreference
            ? defaults.bool(forKey: DefaultsKey.showSidebarUpdateReminders)
            : true
        self.dismissedSidebarUpdateIdentifier = defaults.string(forKey: DefaultsKey.dismissedSidebarUpdateIdentifier)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        super.init()
        updaterDelegate.service = self
        userDriverDelegate.service = self
    }
```

- [ ] **Step 4: Add service methods for update availability and dismissal**

Add these methods inside `SparkleUpdaterService` before `prepareForSparkleUserInterface()`:

```swift
func dismissCurrentSidebarUpdateReminder() {
    guard let availableUpdateIdentifier else { return }
    dismissedSidebarUpdateIdentifier = availableUpdateIdentifier
    defaults.set(availableUpdateIdentifier, forKey: DefaultsKey.dismissedSidebarUpdateIdentifier)
}

func markUpdateAvailable(identifier: String, displayVersion: String?) {
    availableUpdateIdentifier = identifier
    availableUpdateDisplayVersion = displayVersion
}

func clearAvailableUpdate() {
    availableUpdateIdentifier = nil
    availableUpdateDisplayVersion = nil
}
```

- [ ] **Step 5: Add Sparkle updater delegate callbacks**

Add this private delegate class below `SparkleUpdaterService` and above `SparkleUserDriverDelegate`:

```swift
private final class SparkleUpdaterDelegate: NSObject, @preconcurrency SPUUpdaterDelegate {
    weak var service: SparkleUpdaterService?

    @MainActor
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        service?.markUpdateAvailable(
            identifier: "\(item.displayVersionString)-\(item.versionString)",
            displayVersion: item.displayVersionString
        )
    }

    @MainActor
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        service?.clearAvailableUpdate()
    }

    @MainActor
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        service?.clearAvailableUpdate()
    }

    @MainActor
    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if choice == .install {
            service?.clearAvailableUpdate()
        }
    }
}
```

If Swift imports `userDidMakeChoice` with a different external label, use the compiler fix-it from `SPUUpdaterDelegate.h`; the Objective-C selector is `updater:userDidMakeChoice:forUpdate:state:`.

- [ ] **Step 6: Build and run focused tests**

Run:

```bash
swift test --filter SparkleUpdateReminderStateTests
swift build
```

Expected: tests PASS and build succeeds. If the Sparkle delegate method labels differ, fix labels only; do not change behavior.

- [ ] **Step 7: Commit**

```bash
git add Sources/Cider/Services/SparkleUpdaterService.swift Tests/CiderTests/SparkleUpdateReminderStateTests.swift
git commit -m "Track Sparkle sidebar update reminders"
```

## Task 3: Add the Settings Toggle

**Files:**
- Modify: `Sources/Cider/Views/Settings/SettingsView.swift`
- Modify: `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift`

- [ ] **Step 1: Add Settings state**

In `Sources/Cider/Views/Settings/SettingsView.swift`, next to the existing updater state:

```swift
@State var automaticallyChecksForUpdates = SparkleUpdaterService.shared.automaticallyChecksForUpdates
@State var showSidebarUpdateReminders = SparkleUpdaterService.shared.showSidebarUpdateReminders
```

- [ ] **Step 2: Persist changes from the new Settings state**

In the same file, near the existing `onChange(of: automaticallyChecksForUpdates)` handler, add:

```swift
.onChange(of: showSidebarUpdateReminders) { _, newValue in
    SparkleUpdaterService.shared.showSidebarUpdateReminders = newValue
}
```

Keep the existing automatic-checks handler unchanged.

- [ ] **Step 3: Render the toggle in Updates**

In `Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift`, inside `SettingsSection(title: "Updates")`, insert this immediately after the existing `SettingsToggleRow(title: "Check for updates automatically", ...)`:

```swift
SettingsToggleRow(
    title: "Show update reminders in sidebar",
    subtitle: "Show a sidebar badge when a new version of Cider is available",
    isOn: $showSidebarUpdateReminders
)
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/Settings/SettingsView.swift Sources/Cider/Views/Settings/SettingsView+SubcategoryContent.swift
git commit -m "Add sidebar update reminder setting"
```

## Task 4: Add Expanded Sidebar Update Row

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`

- [ ] **Step 1: Observe the updater service in the sidebar panel**

In `SidebarProfilePanel`, add this alongside `authService` and `syncService`:

```swift
@ObservedObject private var updaterService = SparkleUpdaterService.shared
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 2: Add the expanded row above Settings**

In the `VStack(spacing: Spacing.xs)` inside `expandedBody`, insert this before the existing `HomeOverviewQuickActionButton(title: "Settings", ...)`:

```swift
if updaterService.shouldShowSidebarUpdateReminder {
    expandedUpdateReminderButton
}
```

- [ ] **Step 3: Add the expanded update button view**

Add this computed view inside `SidebarProfilePanel`, near the other private view helpers:

```swift
private var expandedUpdateReminderButton: some View {
    Button {
        updaterService.checkForUpdates()
    } label: {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 18, height: 18)

            Text("Update Available")
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Button {
                updaterService.dismissCurrentSidebarUpdateReminder()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.microSemibold)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide this update reminder")
        }
        .padding(.horizontal, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: HomeOverviewDesign.quickActionButtonHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.controlAccent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.controlAccent.opacity(0.35), lineWidth: 1)
                )
        )
    }
    .buttonStyle(.plain)
    .help("Check for updates")
}
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: build succeeds. If SwiftUI complains about nested `Button`, replace the inner dismiss `Button` with an `Image` plus `.simultaneousGesture(TapGesture().onEnded { updaterService.dismissCurrentSidebarUpdateReminder() })`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/CiderPanelView+SidebarFooter.swift
git commit -m "Show expanded sidebar update reminder"
```

## Task 5: Add Collapsed Badge and Pulse

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`

- [ ] **Step 1: Add badge overlay to the compact profile button**

In `compactBody`, find the `Circle()` avatar inside the top expand-profile button and add an overlay after the existing `overlay` that draws `person.fill`:

```swift
.overlay(alignment: .topTrailing) {
    if updaterService.shouldShowSidebarUpdateReminder {
        updateReminderBadge
            .offset(x: 2, y: -2)
    }
}
```

The full avatar block should remain a `Circle()` with the existing fill, frame, and person icon overlay.

- [ ] **Step 2: Add badge to the compact settings icon**

In the `HStack(spacing: Spacing.xs)` of compact icon buttons, replace the current Settings `compactIconButton(...)` call with:

```swift
compactIconButton(
    systemImage: "gearshape",
    help: updaterService.shouldShowSidebarUpdateReminder ? "Update Available" : "Settings",
    action: {
        if updaterService.shouldShowSidebarUpdateReminder {
            updaterService.checkForUpdates()
        } else {
            onOpenSettings()
        }
    }
)
.overlay(alignment: .topTrailing) {
    if updaterService.shouldShowSidebarUpdateReminder {
        updateReminderBadge
            .offset(x: -4, y: 3)
    }
}
```

- [ ] **Step 3: Add the badge view**

Add this computed view inside `SidebarProfilePanel`:

```swift
private var updateReminderBadge: some View {
    Circle()
        .fill(CiderColors.controlAccent)
        .frame(width: 7, height: 7)
        .shadow(color: CiderColors.controlAccent.opacity(reduceMotion ? 0.25 : 0.45), radius: reduceMotion ? 2 : 5)
        .scaleEffect(reduceMotion ? 1 : 1.08)
        .animation(reduceMotion ? .none : .easeInOut(duration: 1.2).repeatCount(3, autoreverses: true), value: updaterService.availableUpdateIdentifier)
        .accessibilityHidden(true)
}
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/CiderPanelView+SidebarFooter.swift
git commit -m "Show collapsed sidebar update badge"
```

## Task 6: Manual Test Hooks and Verification

**Files:**
- Modify: `Sources/Cider/Services/SparkleUpdaterService.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+SidebarFooter.swift`

- [ ] **Step 1: Add debug-only test hooks if manual Sparkle appcast testing is slow**

If a real appcast update is not available during implementation, add this debug-only method to `SparkleUpdaterService`:

```swift
#if DEBUG
func simulateAvailableUpdateForDebugMenu(identifier: String = "debug-update-1", displayVersion: String = "Debug Update") {
    markUpdateAvailable(identifier: identifier, displayVersion: displayVersion)
}
#endif
```

Do not call this from production UI. Use it only from LLDB or a temporary local debug call that is removed before commit.

- [ ] **Step 2: Run all focused checks**

Run:

```bash
swift test --filter SparkleUpdateReminderStateTests
swift test --filter SparkleUpdaterWindowOrderingTests
swift build
```

Expected: all tests pass and build succeeds.

- [ ] **Step 3: Manual UI verification**

Run the macOS app from Xcode or the existing local app workflow, then verify:

1. Settings > General > Startup > Updates shows `Show update reminders in sidebar` below `Check for updates automatically`.
2. With a simulated or real available update and the toggle on, expanded sidebar shows `Update Available` above `Settings`.
3. Clicking `Update Available` opens the existing Sparkle update flow.
4. Clicking the row dismiss control hides the row for the current update identifier.
5. Collapsed sidebar shows a small badge when the update is available and not dismissed.
6. Turning the Settings toggle off hides both expanded row and collapsed badge.
7. Turning Reduce Motion on in macOS accessibility settings removes visible pulsing.

- [ ] **Step 4: Remove temporary debug calls**

Run:

```bash
rg -n "debug-update-1|Debug Update" Sources Tests
```

Expected: no matches. If the optional `simulateAvailableUpdateForDebugMenu` method was useful, it may remain under `#if DEBUG`, but no production call sites should reference it.

- [ ] **Step 5: Final commit**

```bash
git add Sources/Cider/Services/SparkleUpdaterService.swift Sources/Cider/Views/CiderPanelView+SidebarFooter.swift
git commit -m "Verify Sparkle sidebar update reminder"
```

## Self-Review

- Spec coverage: Tasks cover update availability state, Settings toggle placement, expanded row, collapsed badge, version-scoped dismissal, Reduce Motion behavior, and verification.
- Marker scan: no unresolved markers or open-ended implementation steps remain.
- Type consistency: plan uses `SparkleUpdateReminderState`, `SparkleUpdaterService.showSidebarUpdateReminders`, `SparkleUpdaterService.shouldShowSidebarUpdateReminder`, and `SparkleUpdaterService.dismissCurrentSidebarUpdateReminder()` consistently.
