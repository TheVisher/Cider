# Reminder Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Cider into a proactive reminder system. Recurring events and reminders fire as local notifications (on-screen) and as agent-delivered messages (remote). The agent can create, modify, and cancel reminders conversationally. No new data model for v1 — reminders are DateCards with surfacing rules.

**Product direction:** Cider should own reminders as first-class local-first life-assistant data rather than treating Apple Reminders, cron jobs, Telegram, or iMessage as the primary system. Until Cider has native replacement capabilities, use the best macOS-native fallback to help the user now — Apple Reminders for reminders, Calendar for calendar events, Contacts for contacts, etc. These fallbacks are bridges, not the source of truth long-term. Gaps discovered through real requests should be documented and folded back into Cider. Example gap: “remind me to check out Open WebUI when I get home” needs location-aware/geofence triggers and Cider-owned notification delivery.

**Architecture:** Five layers built in order:
1. Fix notification scheduling to support multi-offset reminders with deterministic IDs
2. Add a ReminderReconciler that runs on launch, vault changes, wake-from-sleep, time zone change, and day rollover
3. Add an outbox folder (`.cider/outbox/`) for agent-delivered iMessage reminders with delivery ledger
4. Add CLI and AI tools so the agent can create/modify recurring DateCards with reminder rules
5. End-to-end testing and validation

**Tech Stack:** Swift, SwiftUI, AppKit, UNUserNotificationCenter, filesystem outbox

**Important codebase rules:**
- Use `os.Logger` — not `print()`
- Build command: `swift build -Xswiftc -warnings-as-errors`
- Never test destructive CLI commands against real vault — use `cider-cli --vault ~/CiderTestVault`
- YAML boards: always use Write tool to rewrite entire file

**Design principles:**
- DateCard is the source of truth for all reminders. No parallel reminders system.
- The LLM is not the scheduler. It writes structured data; the reconciler acts on it.
- Local notifications use deterministic identifiers for idempotent scheduling.
- The outbox is a filesystem message bus — Cider writes, the agent reads and sends.
- Launch-at-login for v1. No launchd, no NSBackgroundActivityScheduler.

**Key design decisions:**
- **Recurring completion:** Recurring DateCards MUST NOT be marked complete from notification actions. `isCompleted` on a recurring card kills the entire series. v1 suppresses the "Mark Complete" notification action on recurring cards. v2 can add per-occurrence acknowledgment if needed.
- **Outbox dedup:** Delivery state is tracked in `.cider/outbox/.delivered` ledger file, not by checking directory contents. Both `outbox/` and `outbox/sent/` are checked before writing new files.
- **CLI update semantics:** `--remind` flags on `event update` REPLACE existing reminder offsets (not append). `--clear-reminders` removes all reminder rules.
- **Date parsing:** CLI uses the existing `yyyy-MM-dd` date format via `dateFormatter` (line 3391), not ISO 8601 timestamps. Plan examples must match.
- **Async notification API:** `UNUserNotificationCenter.pendingNotificationRequests()` uses a completion handler. A `withCheckedContinuation` wrapper is required.

---

## Future Gap: Location-Aware Reminders / Geofencing

This plan covers time/date reminders first. Real user request captured on 2026-05-01: “Remind me to check out Open WebUI when I get home.” Desired Cider-native behavior:

- user can create a reminder with trigger `when_at_place: home`
- Cider stores the reminder locally and links it to the relevant bookmark/note/project when applicable
- mobile/location layer detects arrival or the host infers “home” via trusted signals where possible
- Cider delivers the notification through its own Dashboard/mobile/agent notification pipeline
- Apple Reminders should be the preferred temporary fallback for reminders; Telegram, iMessage, or cron may be transport/workaround options, but not the source of truth
- external reminder fallbacks can fail or hang on OS authorization prompts, so agents must verify creation before claiming success
- once macOS Reminders permission is granted, Apple Reminders can successfully deliver notifications through the user's Apple ecosystem, including Apple Watch; verified 2026-05-01 with a 9:30 AM test reminder that the user received on their watch and completed

Likely additions beyond this v1 plan:

- place model: home/work/saved locations with optional geofence radius
- reminder trigger model beyond `remindBeforeMinutes`
- mobile companion or system integration for location updates
- privacy controls for location storage and trigger evaluation
- CLI/AI affordance: `reminder create --title ... --when-at home`

---

## Existing Infrastructure

| Component | File | What exists |
|-----------|------|-------------|
| DateCard model | `Models/DateCard.swift:32-87` | Recurrence rules (daily/weekly/monthly/yearly), `nextOccurrence()`, `effectiveDate()`, `urgency()`. Single `isCompleted`/`completedAt` — no per-occurrence completion. |
| SurfacingRule | `Models/SurfacingRule.swift:3-35` | Three types: `pinUntilDone`, `surfaceDaysBeforeDate`, `remindBeforeMinutes`. Uses `integerValue` for days/minutes. `DateCard.rules` is already an array — multi-offset is just multiple enabled `remindBeforeMinutes` rules. |
| DateCardNotificationService | `Services/DateCardNotificationService.swift` | Schedules UNNotifications, but: wipes ALL pending on each reschedule (line 105), only reads first `remindBeforeMinutes` rule (line 120), uses non-deterministic identifiers. Notification action "MARK_COMPLETE" (line 44) marks the whole card complete — breaks recurring cards. |
| Birthday projection | `Services/LibraryItemEditor.swift:131-170` | Creates yearly recurring DateCards linked to contacts. Only called from UI editor, not from CLI. |
| AppDelegate integration | `App/AppDelegate.swift:204-220` | Reschedules on launch + debounced on DateCardStorage changes |
| AI tools | `Services/AI/FoundationModelsProvider.swift:21-46` | `GetUpcomingEventsTool()` exists for reading. No create/update/cancel tools. |
| CLI commands | `CiderCLI/CiderCLI.swift:1038-1135` | `event create/update/delete/list/export`. No recurrence, no surfacing rules. Date parsing uses `yyyy-MM-dd` format. |
| CLI contact birthday | `CiderCLI/CiderCLI.swift:1168` | `contact create/update --birthday` stores birthday on contact but does NOT create linked recurring DateCard. |
| Outbox / iMessage | None | No outbox folder. iMessage delivery is handled by external Claude Code plugin, not Cider. |

---

## File Map

| File | Action | Task | Purpose |
|------|--------|------|---------|
| `Services/DateCardNotificationService.swift` | **Modify** | 1 | Deterministic IDs, multi-offset, bounded horizon, targeted removal, suppress complete on recurring |
| `Services/ReminderReconciler.swift` | **Create** | 2 | Periodic reconciliation — launch, wake, time zone change, day rollover, vault change |
| `App/AppDelegate.swift` | **Modify** | 2 | Wire reconciler lifecycle |
| `Utilities/StoragePaths.swift` | **Modify** | 3 | Add `.cider/outbox/` path constant |
| `Services/ReminderOutbox.swift` | **Create** | 3 | Write outbox files for agent-delivered reminders with delivery ledger |
| `CiderCLI/CiderCLI.swift` | **Modify** | 4 | Add recurrence + surfacing rule flags to `event create/update`, fix birthday gap |
| `Services/LibraryItemEditor.swift` | **Modify** | 4 | Extract birthday DateCard creation into reusable API |
| `Services/AI/Tools/CreateReminderTool.swift` | **Create** | 5 | AI tool: create recurring DateCard with reminder rules |
| `Services/AI/Tools/CancelReminderTool.swift` | **Create** | 5 | AI tool: cancel/disable reminder rules on a DateCard |
| `Services/AI/FoundationModelsProvider.swift` | **Modify** | 5 | Register new tools |

---

## Task 1: Fix notification scheduling

The current `DateCardNotificationService` has four problems:
- Calls `removeAllPendingNotificationRequests()` (line 105) — wipes everything, including unrelated notifications
- Only reads the first `remindBeforeMinutes` rule (line 120) — ignores additional offsets
- Uses `"datecard-\(id)"` as identifier (line 151) — not unique per occurrence or offset
- "MARK_COMPLETE" notification action (line 44) marks recurring cards complete, killing the series

**Files:**
- Modify: `Sources/Cider/Services/DateCardNotificationService.swift`

- [ ] **Step 1: Add async wrapper for pendingNotificationRequests**

`UNUserNotificationCenter.pendingNotificationRequests()` uses a completion handler, not async/await. Add a small wrapper:

```swift
private func pendingRequests() async -> [UNNotificationRequest] {
    await withCheckedContinuation { continuation in
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            continuation.resume(returning: requests)
        }
    }
}
```

- [ ] **Step 2: Switch to deterministic notification identifiers**

Replace the current identifier format `"datecard-\(dateCard.id.uuidString)"` with a deterministic format that encodes the card, occurrence, and offset:

```
"datecard-{cardID}-{occurrenceISO}-{minutesBefore}"
```

Example: `"datecard-A1B2C3D4-2026-05-01T000000-1440"` (rent reminder, 1 day before May 1st)

Use a compact ISO format without colons (colons can cause issues in identifiers): `yyyyMMddTHHmmss`.

This allows multiple notifications per card (different offsets) and per occurrence (recurring events).

- [ ] **Step 3: Replace removeAllPendingNotificationRequests with targeted reconciliation**

Instead of wiping all pending notifications:

```swift
// Get current pending requests via async wrapper
let pending = await pendingRequests()
let datecardIDs = pending.map(\.identifier).filter { $0.hasPrefix("datecard-") }

// Compute the set of identifiers we WANT to have scheduled
let desiredIDs: Set<String> = // ... computed from current cards + rules + horizon

// Remove only datecard notifications that are no longer desired
let staleIDs = datecardIDs.filter { !desiredIDs.contains($0) }
if !staleIDs.isEmpty {
    center.removePendingNotificationRequests(withIdentifiers: staleIDs)
}

// Add only notifications that aren't already pending
let existingIDs = Set(datecardIDs)
let newRequests = allDesiredRequests.filter { !existingIDs.contains($0.identifier) }
for request in newRequests {
    try? await center.add(request)
}
```

This is the "reconcile desired state" pattern — idempotent and safe. Non-datecard notifications (e.g., future notification types) are never touched.

- [ ] **Step 4: Consume ALL remindBeforeMinutes rules per card**

Replace the current logic that reads only the first rule (line 120-126) with a loop over all enabled `remindBeforeMinutes` rules:

```swift
let reminderRules = dateCard.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }

// If no explicit rules, use config default
let offsets: [Int] = reminderRules.isEmpty
    ? [config.defaultReminderMinutes]
    : reminderRules.compactMap(\.integerValue)

for minutesBefore in offsets {
    let fireDate = targetDate.addingTimeInterval(-Double(minutesBefore) * 60)
    guard fireDate > now else { continue }
    
    let identifier = "datecard-\(dateCard.id.uuidString)-\(compactISO(targetDate))-\(minutesBefore)"
    // ... create UNNotificationRequest with UNCalendarNotificationTrigger
}
```

- [ ] **Step 5: Schedule a bounded horizon (next 7 days)**

Don't try to schedule notifications for all future occurrences of a recurring event. Compute occurrences within a 7-day window and schedule only those. The reconciler (Task 2) will advance the window periodically.

```swift
let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now)!
var occurrences: [Date] = []
var cursor = dateCard.effectiveDate(now: now)
while cursor <= horizon {
    occurrences.append(cursor)
    guard let next = dateCard.nextOccurrence(after: cursor) else { break }
    cursor = next
}
```

- [ ] **Step 6: Suppress "Mark Complete" action on recurring card notifications**

In the notification content construction, check if the card has a recurrence rule. If yes, use a different notification category that omits the "MARK_COMPLETE" action:

```swift
let isRecurring = dateCard.recurrenceRule != nil
content.categoryIdentifier = isRecurring 
    ? Self.recurringCategoryIdentifier   // only has "OPEN" action
    : Self.categoryIdentifier            // has "OPEN" + "MARK_COMPLETE" actions
```

Register the new category on setup:

```swift
private static let recurringCategoryIdentifier = "datecard-reminder-recurring"

// In registerNotificationCategories():
let recurringCategory = UNNotificationCategory(
    identifier: recurringCategoryIdentifier,
    actions: [openAction],  // NO complete action
    intentIdentifiers: []
)
```

This prevents users from accidentally killing a recurring series by tapping "Complete" on a single occurrence's notification.

- [ ] **Step 7: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 8: Commit**

```bash
git add Sources/Cider/Services/DateCardNotificationService.swift
git commit -m "fix: deterministic notification IDs, multi-offset rules, bounded horizon, recurring-safe actions"
```

---

## Task 2: Create ReminderReconciler

A service that periodically ensures notification state matches the current vault. Runs on launch, vault changes, wake-from-sleep, time zone change, and day rollover.

**Files:**
- Create: `Sources/Cider/Services/ReminderReconciler.swift`
- Modify: `Sources/Cider/App/AppDelegate.swift`

- [ ] **Step 1: Create ReminderReconciler service**

```swift
import Foundation
import os

@MainActor
final class ReminderReconciler {
    static let shared = ReminderReconciler()
    private static let logger = Logger(subsystem: "com.cider.app", category: "ReminderReconciler")
    
    private var dayRolloverTimer: Timer?
    private var lastReconcileDate: Date?
    
    /// Call on app launch, wake-from-sleep, time zone change, vault changes, and day rollover.
    func reconcile() {
        let now = Date()
        Self.logger.debug("Reconciling reminders at \(now)")
        
        // 1. Reschedule local notifications (uses the fixed service from Task 1)
        DateCardNotificationService.shared.rescheduleAll()
        
        // 2. Check outbox for agent-delivered reminders (Task 3)
        ReminderOutbox.shared.processReminders()
        
        lastReconcileDate = now
    }
    
    /// Start periodic reconciliation.
    func start() {
        // Day rollover: schedule a timer for midnight + 1 minute
        scheduleDayRolloverTimer()
        
        // Wake-from-sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.logger.debug("Wake from sleep — reconciling")
            self?.reconcile()
        }
        
        // Machine wake (covers lid-open, power-on — broader than screensDidWake)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.logger.debug("Machine wake — reconciling")
            self?.reconcile()
        }
        
        // Time zone change (travel, manual clock change)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.logger.debug("Time zone changed — reconciling")
            self?.reconcile()
        }
        
        // Initial reconcile
        reconcile()
    }
    
    func stop() {
        dayRolloverTimer?.invalidate()
        dayRolloverTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    private func scheduleDayRolloverTimer() {
        dayRolloverTimer?.invalidate()
        
        // Compute seconds until next midnight + 60 seconds
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let fireDate = tomorrow.addingTimeInterval(60) // 1 minute after midnight
        let interval = fireDate.timeIntervalSince(now)
        
        dayRolloverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Self.logger.debug("Day rollover — reconciling")
            Task { @MainActor in
                self?.reconcile()
                self?.scheduleDayRolloverTimer() // Schedule next day's timer
            }
        }
    }
}
```

- [ ] **Step 2: Wire reconciler into AppDelegate**

In `AppDelegate.swift`, replace the current notification scheduling setup (lines 204-220) with the reconciler:

```swift
// Start reminder reconciler (handles local notifications + outbox)
ReminderReconciler.shared.start()

// Subscribe to DateCardStorage changes — reconcile on vault change
self.dateCardNotificationCancellable = DateCardStorage.shared.$dateCards
    .debounce(for: .seconds(2), scheduler: RunLoop.main)
    .sink { _ in
        ReminderReconciler.shared.reconcile()
    }
```

Keep the notification permission request — the reconciler will need it.

- [ ] **Step 3: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add Sources/Cider/Services/ReminderReconciler.swift Sources/Cider/App/AppDelegate.swift
git commit -m "feat: add ReminderReconciler — launch, wake, time zone, day rollover, vault change"
```

---

## Task 3: Add outbox for agent-delivered iMessage reminders

Cider writes reminder files to `.cider/outbox/`. The iMessage agent (Claude Code running in the vault) picks them up and sends them. This is a filesystem message bus — no IPC needed.

**Dedup strategy:** A `.delivered` ledger file in the outbox directory tracks all delivered reminder IDs. Before writing a new outbox file, check the ledger AND the `outbox/` and `outbox/sent/` directories. The agent moves processed files to `sent/`, and the ledger provides a durable backup in case the agent deletes files instead of moving them.

**Files:**
- Create: `Sources/Cider/Services/ReminderOutbox.swift`
- Modify: `Sources/Cider/Utilities/StoragePaths.swift`

- [ ] **Step 1: Add outbox path to StoragePaths**

Add to StoragePaths:

```swift
static var outboxDirectory: URL {
    ciderDirectory.appendingPathComponent("outbox")
}
```

- [ ] **Step 2: Create ReminderOutbox service**

```swift
import Foundation
import os

@MainActor
final class ReminderOutbox {
    static let shared = ReminderOutbox()
    private static let logger = Logger(subsystem: "com.cider.app", category: "ReminderOutbox")
    
    /// Ledger file tracking all delivered reminder IDs to prevent duplicates.
    private var deliveredLedgerURL: URL {
        StoragePaths.outboxDirectory.appendingPathComponent(".delivered")
    }
    
    /// Check which reminders are due and write outbox files for agent delivery.
    func processReminders() {
        let dateCards = DateCardStorage.shared.dateCards
        let now = Date()
        let config = CiderConfig.load()
        
        guard config.enableAgentReminders else { return }
        
        for card in dateCards {
            processCard(card, now: now)
        }
    }
    
    private func processCard(_ card: DateCard, now: Date) {
        // Skip completed non-recurring cards. Recurring cards ignore isCompleted
        // (completion semantics are per-occurrence, not per-series).
        if card.isCompleted, card.recurrenceRule == nil { return }
        
        let reminderRules = card.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }
        guard !reminderRules.isEmpty else { return }
        
        // Compute occurrences in the next 24 hours
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        var cursor = card.effectiveDate(now: now)
        
        while cursor <= horizon {
            for rule in reminderRules {
                let minutesBefore = rule.integerValue ?? 15
                let fireDate = cursor.addingTimeInterval(-Double(minutesBefore) * 60)
                
                // Fire if the reminder time is within the last 5 minutes (catch window)
                // and hasn't been delivered yet
                if fireDate <= now, fireDate > now.addingTimeInterval(-5 * 60) {
                    let fileID = outboxFileID(cardID: card.id, occurrence: cursor, offset: minutesBefore)
                    if !isDelivered(fileID) {
                        writeOutboxFile(card: card, occurrence: cursor, minutesBefore: minutesBefore, fileID: fileID)
                        markDelivered(fileID)
                    }
                }
            }
            
            guard let next = card.nextOccurrence(after: cursor) else { break }
            cursor = next
        }
    }
    
    // MARK: - File ID
    
    private func outboxFileID(cardID: UUID, occurrence: Date, offset: Int) -> String {
        let formatter = ISO8601DateFormatter()
        let iso = formatter.string(from: occurrence)
        return "\(cardID.uuidString)-\(iso)-\(offset)min"
    }
    
    // MARK: - Delivery Dedup (3 sources: ledger, outbox/, outbox/sent/)
    
    private func isDelivered(_ fileID: String) -> Bool {
        // Check 1: ledger file
        if ledgerContains(fileID) { return true }
        
        // Check 2: file still in outbox/ (agent hasn't picked it up yet)
        let outboxURL = StoragePaths.outboxDirectory.appendingPathComponent("\(fileID).md")
        if FileManager.default.fileExists(atPath: outboxURL.path) { return true }
        
        // Check 3: file in sent/ (agent already delivered it)
        let sentURL = StoragePaths.outboxDirectory
            .appendingPathComponent("sent")
            .appendingPathComponent("\(fileID).md")
        if FileManager.default.fileExists(atPath: sentURL.path) { return true }
        
        return false
    }
    
    private func ledgerContains(_ fileID: String) -> Bool {
        guard let data = try? String(contentsOf: deliveredLedgerURL, encoding: .utf8) else { return false }
        return data.contains(fileID)
    }
    
    private func markDelivered(_ fileID: String) {
        let dir = StoragePaths.outboxDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let entry = "\(fileID)\n"
        if let handle = try? FileHandle(forWritingTo: deliveredLedgerURL) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? entry.write(to: deliveredLedgerURL, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Write Outbox File
    
    private func writeOutboxFile(card: DateCard, occurrence: Date, minutesBefore: Int, fileID: String) {
        let dir = StoragePaths.outboxDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        let timeDescription: String
        if minutesBefore == 0 {
            timeDescription = "now"
        } else if minutesBefore < 60 {
            timeDescription = "in \(minutesBefore) minutes"
        } else if minutesBefore < 1440 {
            let hours = minutesBefore / 60
            timeDescription = "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = minutesBefore / 1440
            timeDescription = "in \(days) day\(days == 1 ? "" : "s")"
        }
        
        let isRecurring = card.recurrenceRule != nil
        let recurringNote = isRecurring ? "\nThis is a recurring reminder (\(card.recurrenceRule!.frequency.rawValue))." : ""
        
        let content = """
        ---
        type: reminder
        cardID: \(card.id.uuidString)
        title: \(card.title)
        occurrence: \(ISO8601DateFormatter().string(from: occurrence))
        minutesBefore: \(minutesBefore)
        recurring: \(isRecurring)
        createdAt: \(ISO8601DateFormatter().string(from: Date()))
        ---
        
        Reminder: \(card.title) is \(timeDescription).
        Date: \(formatter.string(from: occurrence))\
        \(card.location.isEmpty ? "" : "\nLocation: \(card.location)")\
        \(card.details.isEmpty ? "" : "\nDetails: \(card.details)")\
        \(recurringNote)
        """
        
        let url = dir.appendingPathComponent("\(fileID).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        Self.logger.info("Wrote outbox reminder: \(fileID)")
    }
}
```

- [ ] **Step 3: Add enableAgentReminders to CiderConfig**

Add a new config property (following the CiderConfig pattern — `decodeIfPresent` + fallback):

```swift
var enableAgentReminders: Bool = false
```

This keeps agent reminders opt-in until the user has a running agent.

- [ ] **Step 4: Add vault CLAUDE.md instructions for the agent**

Document the outbox convention in the vault's CLAUDE.md so the agent knows to check it:

```markdown
## Reminder Outbox

Cider writes reminder notifications to `.cider/outbox/` as Markdown files with YAML frontmatter.

### Processing outbox files

On each loop iteration or vault change:
1. List files in `.cider/outbox/` (exclude `sent/` subdirectory and `.delivered` ledger)
2. For each `.md` file:
   a. Read the file — the body contains the reminder message to send
   b. Send the message to the user via iMessage
   c. Move the file to `.cider/outbox/sent/` as a delivery record
3. Do NOT delete outbox files — the `sent/` folder and `.delivered` ledger track delivery state

### File format

```yaml
---
type: reminder
cardID: <uuid>
title: <event title>
occurrence: <ISO8601 date of the event>
minutesBefore: <offset in minutes>
recurring: <true|false>
createdAt: <ISO8601 timestamp when outbox file was written>
---

Reminder: <title> is <time description>.
Date: <formatted date>
Location: <if any>
Details: <if any>
```

### Creating reminders

Users may text you to create reminders. Use the `cider-cli event create` command:

```bash
cider-cli event create "<title>" --date <yyyy-MM-dd> --frequency <daily|weekly|monthly|yearly> --remind <minutes>
```

You can specify `--remind` multiple times for multi-stage reminders (e.g., `--remind 1440 --remind 60 --remind 0` for day-before, hour-before, and at-time).
```

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Services/ReminderOutbox.swift Sources/Cider/Utilities/StoragePaths.swift Sources/Cider/Models/CiderConfig.swift
git commit -m "feat: add reminder outbox with delivery ledger for agent iMessage notifications"
```

---

## Task 4: Extend CLI with recurrence and reminder rules

The CLI `event create` currently has no support for recurrence rules or surfacing rules. Agents need to create "pay rent on the 1st every month with 1-day and same-day reminders" from the command line.

Also: fix the birthday gap where `contact create --birthday` doesn't create the linked DateCard.

**CLI date format:** The existing CLI date parser uses `yyyy-MM-dd` format (via `dateFormatter` at line 3391). All examples in this task use that format, not ISO 8601 timestamps.

**Files:**
- Modify: `Sources/CiderCLI/CiderCLI.swift` (handleEvent function, ~line 1038)
- Modify: `Sources/CiderCLI/CiderCLI.swift` (handleContact function, ~line 1168)
- Modify: `Sources/Cider/Services/LibraryItemEditor.swift`

- [ ] **Step 1: Add recurrence flags to `event create`**

Add these flags to the `event create` subcommand:

```
--frequency daily|weekly|monthly|yearly
--interval <N>           (default: 1)
--end-date <yyyy-MM-dd>  (optional recurrence end date)
```

Parse them and construct a `DateCardRecurrenceRule`:

```swift
if let freqStr = parseFlag("--frequency", from: &args) {
    let freq: DateCardRecurrenceFrequency
    switch freqStr.lowercased() {
    case "daily": freq = .daily
    case "weekly": freq = .weekly
    case "monthly": freq = .monthly
    case "yearly": freq = .yearly
    default:
        print("Error: Invalid frequency. Use daily, weekly, monthly, or yearly.")
        return
    }
    let interval = parseFlag("--interval", from: &args).flatMap(Int.init) ?? 1
    let endDate = parseFlag("--end-date", from: &args).flatMap { dateFormatter.date(from: $0) }
    card.recurrenceRule = DateCardRecurrenceRule(frequency: freq, interval: interval, endDate: endDate)
}
```

- [ ] **Step 2: Add reminder rule flags to `event create`**

Add flags:

```
--remind <minutes>       (can be specified multiple times for multi-offset)
```

Parse and construct `SurfacingRule` entries:

```swift
let remindValues = parseFlagAll("--remind", from: &args)
for value in remindValues {
    guard let minutes = Int(value) else {
        print("Error: --remind requires an integer (minutes before event)")
        return
    }
    let rule = SurfacingRule(
        id: UUID(),
        type: .remindBeforeMinutes,
        integerValue: minutes,
        isEnabled: true,
        createdAt: Date(),
        updatedAt: Date()
    )
    card.rules.append(rule)
}
```

Usage example:
```bash
cider-cli event create "Pay Rent" --date 2026-05-01 --frequency monthly --remind 1440 --remind 0
# Creates monthly recurring event with reminders at 1 day before and day-of
```

- [ ] **Step 3: Add reminder rule flags to `event update` (replace semantics)**

On `event update`, `--remind` flags REPLACE all existing `remindBeforeMinutes` rules (not append). Add `--clear-reminders` to remove all reminder rules.

```swift
// On update: if any --remind flags provided, replace existing reminder rules
let remindValues = parseFlagAll("--remind", from: &args)
if !remindValues.isEmpty {
    // Remove existing remindBeforeMinutes rules
    card.rules.removeAll { $0.type == .remindBeforeMinutes }
    // Add new ones
    for value in remindValues {
        guard let minutes = Int(value) else {
            print("Error: --remind requires an integer (minutes before event)")
            return
        }
        card.rules.append(SurfacingRule(
            id: UUID(),
            type: .remindBeforeMinutes,
            integerValue: minutes,
            isEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
}

// --clear-reminders removes all reminder rules
if args.contains("--clear-reminders") {
    card.rules.removeAll { $0.type == .remindBeforeMinutes }
    args.removeAll { $0 == "--clear-reminders" }
}
```

- [ ] **Step 4: Fix birthday gap in contact create/update**

In the CLI's `handleContact` for `create` and `update`, when `--birthday` is provided, call `LibraryItemEditor.createOrUpdateBirthdayDateCard`:

```swift
if let birthdayStr = parseFlag("--birthday", from: &args),
   let birthday = parseDateLoose(birthdayStr) {
    contact.birthday = birthday
    // Create linked recurring DateCard for birthday
    LibraryItemEditor.createOrUpdateBirthdayDateCard(for: contact, birthday: birthday)
}
```

This ensures agent-created contacts with birthdays get the same linked yearly DateCard as UI-created contacts.

- [ ] **Step 5: Update help text**

Add the new flags to `printUsage()`:

```
event create <title> --date <yyyy-MM-dd> [--frequency daily|weekly|monthly|yearly] [--interval N] [--end-date yyyy-MM-dd] [--remind <minutes>]... [--folder <name>]
event update <id> [--title <new>] [--date <yyyy-MM-dd>] [--remind <minutes>]... [--clear-reminders]
```

- [ ] **Step 6: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 7: Commit**

```bash
git add Sources/CiderCLI/CiderCLI.swift Sources/Cider/Services/LibraryItemEditor.swift
git commit -m "feat: CLI event create/update with recurrence rules, multi-offset reminders, and birthday fix"
```

---

## Task 5: Add AI tools for reminder management

The iMessage agent needs to create and cancel reminders conversationally. Add tools that the LLM can call.

**Files:**
- Create: `Sources/Cider/Services/AI/Tools/CreateReminderTool.swift`
- Create: `Sources/Cider/Services/AI/Tools/CancelReminderTool.swift`
- Modify: `Sources/Cider/Services/AI/FoundationModelsProvider.swift`

- [ ] **Step 1: Create CreateReminderTool**

An AI tool that creates a recurring DateCard with surfacing rules. The LLM parses natural language into structured parameters.

Parameters the tool should accept:
- `title: String` — "Pay Rent", "Mom's Birthday", etc.
- `date: String` — `yyyy-MM-dd` date for the first occurrence
- `frequency: String?` — "daily", "weekly", "monthly", "yearly" (nil = one-time)
- `interval: Int?` — repeat interval (default 1)
- `allDay: Bool?` — default true for reminders without specific time
- `remindMinutesBefore: [Int]?` — array of offsets, e.g. [1440, 0] for "1 day before and day-of"
- `location: String?`
- `details: String?`

The tool creates a DateCard via `DateCardStorage.shared.createDateCard(...)`, attaches recurrence and surfacing rules, then triggers reconciliation via `ReminderReconciler.shared.reconcile()`.

- [ ] **Step 2: Create CancelReminderTool**

An AI tool that finds and disables or deletes a reminder. Parameters:
- `title: String` — fuzzy match against existing DateCards
- `deleteCard: Bool?` — if true, delete the DateCard entirely. If false, just disable reminder rules.

- [ ] **Step 3: Register tools in FoundationModelsProvider**

Add to the tools array (line 21 of FoundationModelsProvider.swift):

```swift
CreateReminderTool(),
CancelReminderTool(),
```

- [ ] **Step 4: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Services/AI/Tools/CreateReminderTool.swift Sources/Cider/Services/AI/Tools/CancelReminderTool.swift Sources/Cider/Services/AI/FoundationModelsProvider.swift
git commit -m "feat: AI tools for creating and cancelling reminders"
```

---

## Task 6: End-to-end testing and validation

- [ ] **Step 1: Test local notification flow**

Create a test DateCard with multiple reminder offsets via CLI:
```bash
cider-cli --vault ~/CiderTestVault event create "Test Reminder" \
  --date 2026-04-12 --remind 5 --remind 0
```

Verify:
- Two pending notifications registered in the system (5 min before and at event time)
- Notifications fire at the correct times
- Re-running the reconciler doesn't create duplicates (check notification count stays the same)

- [ ] **Step 2: Test recurring event scheduling**

```bash
cider-cli --vault ~/CiderTestVault event create "Daily Standup" \
  --date 2026-04-13 --frequency daily --remind 15
```

Verify:
- Only the next 7 days of occurrences are scheduled (bounded horizon)
- After day rollover (or manual reconcile), the window advances
- Tapping the notification does NOT show "Mark Complete" (recurring card)

- [ ] **Step 3: Test outbox flow**

Enable agent reminders in config. Create a DateCard with a reminder offset that falls within the 5-minute catch window. Verify:
- An outbox file appears in `.cider/outbox/`
- The file ID appears in `.cider/outbox/.delivered`
- Re-running the reconciler does NOT create a duplicate file

- [ ] **Step 4: Test birthday flow from CLI**

```bash
cider-cli --vault ~/CiderTestVault contact create "Test Person" --birthday 1990-04-15
```

Verify a linked yearly recurring DateCard is created with title "Test Person Birthday".

- [ ] **Step 5: Test update replace semantics**

```bash
cider-cli --vault ~/CiderTestVault event update <id> --remind 30
```

Verify: previous reminder offsets are replaced, not appended.

```bash
cider-cli --vault ~/CiderTestVault event update <id> --clear-reminders
```

Verify: all reminder rules removed.

- [ ] **Step 6: Commit test results / cleanup**

```bash
git commit -m "test: validate reminder engine end-to-end"
```

---

## Outbox Protocol (for agent CLAUDE.md)

The agent needs to know how to process outbox files. Add this to the vault's CLAUDE.md:

```markdown
## Reminder Outbox

Cider writes reminder notifications to `.cider/outbox/` as Markdown files with YAML frontmatter.

### Processing outbox files

On each loop iteration or vault change:
1. List files in `.cider/outbox/` (exclude `sent/` subdirectory and `.delivered` ledger)
2. For each `.md` file:
   a. Read the file — the body contains the reminder message to send
   b. Send the message to the user via iMessage
   c. Move the file to `.cider/outbox/sent/` as a delivery record
3. Do NOT delete outbox files — the `sent/` folder and `.delivered` ledger track delivery state

### File format

```yaml
---
type: reminder
cardID: <uuid>
title: <event title>
occurrence: <ISO8601 date of the event>
minutesBefore: <offset in minutes>
recurring: <true|false>
createdAt: <ISO8601 timestamp when outbox file was written>
---

Reminder: <title> is <time description>.
Date: <formatted date>
Location: <if any>
Details: <if any>
```

### Creating reminders

Users may text you to create reminders. Use the `cider-cli event create` command:

```bash
cider-cli event create "<title>" --date <yyyy-MM-dd> --frequency <daily|weekly|monthly|yearly> --remind <minutes>
```

You can specify `--remind` multiple times for multi-stage reminders (e.g., `--remind 1440 --remind 60 --remind 0` for day-before, hour-before, and at-time).
```

---

## Future work (not in this plan)

- **Per-occurrence acknowledgment:** v2 model for recurring cards — track which occurrences have been acknowledged without marking the series complete. Could use a `completedOccurrences: [Date]` array on DateCard or a separate SQLite table.
- **"Remind me again in an hour"** — Agent creates a one-time DateCard with `startAt` = now + 1 hour and `--remind 0`. The reconciler handles the rest.
- **Delivery ledger in SQLite** — When agent texts become the primary channel, migrate from `.delivered` text file to a proper `(cardID, occurrence, offset) → delivered_at` table for stricter dedup and querying.
- **Snooze from notification** — Add a UNNotification action that creates a +1hr one-time DateCard.
- **Digest messages** — "You have 3 birthdays this week" — a daily summary outbox file composed by the reconciler.
- **Launch at login** — Add `SMAppService.mainApp.register()` for login-item behavior.
