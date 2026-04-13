# Reminder Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Cider into a proactive reminder system. Recurring events and reminders fire as local notifications (on-screen) and as agent-delivered iMessages (remote). The iMessage agent can create, modify, and cancel reminders conversationally. No new data model — reminders are DateCards with surfacing rules.

**Architecture:** Four layers built in order:
1. Fix notification scheduling to support multi-offset reminders with deterministic IDs
2. Add a ReminderReconciler that runs on launch, vault changes, wake-from-sleep, and day rollover
3. Add an outbox folder (`.cider/outbox/`) for agent-delivered iMessage reminders
4. Add CLI and AI tools so the agent can create/modify recurring DateCards with reminder rules

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

---

## Existing Infrastructure

| Component | File | What exists |
|-----------|------|-------------|
| DateCard model | `Models/DateCard.swift:32-87` | Recurrence rules (daily/weekly/monthly/yearly), `nextOccurrence()`, `effectiveDate()`, `urgency()` |
| SurfacingRule | `Models/SurfacingRule.swift:3-35` | Three types: `pinUntilDone`, `surfaceDaysBeforeDate`, `remindBeforeMinutes`. Uses `integerValue` for days/minutes. `DateCard.rules` is already an array — multi-offset is just multiple rules. |
| DateCardNotificationService | `Services/DateCardNotificationService.swift` | Schedules UNNotifications, but: wipes ALL pending on each reschedule (line 105), only reads first `remindBeforeMinutes` rule (line 120), uses non-deterministic identifiers |
| Birthday projection | `Services/LibraryItemEditor.swift:131-170` | Creates yearly recurring DateCards linked to contacts. Only called from UI editor, not from CLI. |
| AppDelegate integration | `App/AppDelegate.swift:204-220` | Reschedules on launch + debounced on DateCardStorage changes |
| AI tools | `Services/AI/FoundationModelsProvider.swift:21-46` | `GetUpcomingEventsTool()` exists for reading. No create/update/cancel tools. |
| CLI commands | `CiderCLI/CiderCLI.swift:1038-1135` | `event create/update/delete/list/export`. No recurrence, no surfacing rules. |
| Outbox / iMessage | None | No outbox folder. iMessage delivery is handled by external Claude Code plugin, not Cider. |

---

## File Map

| File | Action | Task | Purpose |
|------|--------|------|---------|
| `Services/DateCardNotificationService.swift` | **Modify** | 1 | Deterministic IDs, multi-offset, bounded horizon, targeted removal |
| `Services/ReminderReconciler.swift` | **Create** | 2 | Periodic reconciliation — launch, wake, day rollover, vault change |
| `App/AppDelegate.swift` | **Modify** | 2 | Wire reconciler lifecycle |
| `Utilities/StoragePaths.swift` | **Modify** | 3 | Add `.cider/outbox/` path constant |
| `Services/ReminderOutbox.swift` | **Create** | 3 | Write outbox files for agent-delivered reminders |
| `CiderCLI/CiderCLI.swift` | **Modify** | 4 | Add recurrence + surfacing rule flags to `event create/update` |
| `Services/LibraryItemEditor.swift` | **Modify** | 4 | Extract birthday DateCard creation into reusable API |
| `Services/AI/Tools/CreateReminderTool.swift` | **Create** | 5 | AI tool: create recurring DateCard with reminder rules |
| `Services/AI/Tools/CancelReminderTool.swift` | **Create** | 5 | AI tool: cancel/disable reminder rules on a DateCard |
| `Services/AI/FoundationModelsProvider.swift` | **Modify** | 5 | Register new tools |

---

## Task 1: Fix notification scheduling

The current `DateCardNotificationService` has three problems:
- Calls `removeAllPendingNotificationRequests()` (line 105) — wipes everything, including unrelated notifications
- Only reads the first `remindBeforeMinutes` rule (line 120) — ignores additional offsets
- Uses `"datecard-\(id)"` as identifier (line 151) — not unique per occurrence or offset

**Files:**
- Modify: `Sources/Cider/Services/DateCardNotificationService.swift`

- [ ] **Step 1: Switch to deterministic notification identifiers**

Replace the current identifier format `"datecard-\(dateCard.id.uuidString)"` with a deterministic format that encodes the card, occurrence, and offset:

```
"datecard-{cardID}-{occurrenceISO}-{minutesBefore}"
```

Example: `"datecard-A1B2C3D4-2026-05-01T00:00:00Z-1440"` (rent reminder, 1 day before May 1st)

This allows multiple notifications per card (different offsets) and per occurrence (recurring events).

- [ ] **Step 2: Replace removeAllPendingNotificationRequests with targeted removal**

Instead of wiping all pending notifications:

```swift
// Collect all datecard-prefixed identifiers from pending requests
let pending = await center.pendingNotificationRequests()
let datecardIDs = pending.map(\.identifier).filter { $0.hasPrefix("datecard-") }

// Compute the set of identifiers we WANT to have scheduled
let desiredIDs: Set<String> = // ... computed from current cards + rules

// Remove only datecard notifications that are no longer desired
let staleIDs = datecardIDs.filter { !desiredIDs.contains($0) }
center.removePendingNotificationRequests(withIdentifiers: staleIDs)

// Add only notifications that aren't already pending
let existingIDs = Set(datecardIDs)
let newRequests = allRequests.filter { !existingIDs.contains($0.identifier) }
```

This is the "reconcile desired state" pattern — idempotent and safe.

- [ ] **Step 3: Consume ALL remindBeforeMinutes rules per card**

Replace the current logic that reads only the first rule (line 120-126) with a loop over all enabled `remindBeforeMinutes` rules:

```swift
let reminderRules = dateCard.rules.filter { $0.type == .remindBeforeMinutes && $0.isEnabled }

for rule in reminderRules {
    let minutesBefore = rule.integerValue ?? config.defaultReminderMinutes
    let fireDate = targetDate.addingTimeInterval(-Double(minutesBefore) * 60)
    guard fireDate > now else { continue }
    
    let identifier = "datecard-\(dateCard.id.uuidString)-\(isoString(targetDate))-\(minutesBefore)"
    // ... create and add UNNotificationRequest
}
```

If a card has no `remindBeforeMinutes` rules, fall back to the config default (current behavior preserved).

- [ ] **Step 4: Schedule a bounded horizon (next 7 days)**

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

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Services/DateCardNotificationService.swift
git commit -m "fix: deterministic notification IDs, multi-offset rules, bounded horizon"
```

---

## Task 2: Create ReminderReconciler

A service that periodically ensures notification state matches the current vault. Runs on launch, vault changes, wake-from-sleep, and day rollover.

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
    
    /// Call on app launch, wake-from-sleep, vault changes, and day rollover.
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
        
        // Wake-from-sleep: observe NSWorkspace notification
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.logger.debug("Wake from sleep — reconciling")
            self?.reconcile()
        }
        
        // Initial reconcile
        reconcile()
    }
    
    func stop() {
        dayRolloverTimer?.invalidate()
        dayRolloverTimer = nil
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
git commit -m "feat: add ReminderReconciler — launch, wake, day rollover, vault change"
```

---

## Task 3: Add outbox for agent-delivered iMessage reminders

Cider writes reminder files to `.cider/outbox/`. The iMessage agent (Claude Code running in the vault) picks them up and sends them. This is a filesystem message bus — no IPC needed.

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

The outbox writes Markdown files that the agent can read and act on. Each file contains the reminder context and delivery instructions.

```swift
import Foundation
import os

@MainActor
final class ReminderOutbox {
    static let shared = ReminderOutbox()
    private static let logger = Logger(subsystem: "com.cider.app", category: "ReminderOutbox")
    
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
        guard !card.isCompleted else { return }
        
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
                // and hasn't been sent yet
                if fireDate <= now, fireDate > now.addingTimeInterval(-5 * 60) {
                    let fileID = outboxFileID(cardID: card.id, occurrence: cursor, offset: minutesBefore)
                    if !outboxFileExists(fileID) {
                        writeOutboxFile(card: card, occurrence: cursor, minutesBefore: minutesBefore, fileID: fileID)
                    }
                }
            }
            
            guard let next = card.nextOccurrence(after: cursor) else { break }
            cursor = next
        }
    }
    
    private func outboxFileID(cardID: UUID, occurrence: Date, offset: Int) -> String {
        let iso = ISO8601DateFormatter().string(from: occurrence)
        return "\(cardID.uuidString)-\(iso)-\(offset)min"
    }
    
    private func outboxFileExists(_ fileID: String) -> Bool {
        let url = StoragePaths.outboxDirectory.appendingPathComponent("\(fileID).md")
        return FileManager.default.fileExists(atPath: url.path)
    }
    
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
            timeDescription = "in \(minutesBefore / 60) hour(s)"
        } else {
            timeDescription = "in \(minutesBefore / 1440) day(s)"
        }
        
        let content = """
        ---
        type: reminder
        cardID: \(card.id.uuidString)
        title: \(card.title)
        occurrence: \(ISO8601DateFormatter().string(from: occurrence))
        minutesBefore: \(minutesBefore)
        createdAt: \(ISO8601DateFormatter().string(from: Date()))
        ---
        
        Reminder: \(card.title) is \(timeDescription).
        Date: \(formatter.string(from: occurrence))
        \(card.location.isEmpty ? "" : "Location: \(card.location)")
        \(card.details.isEmpty ? "" : "\nDetails: \(card.details)")
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
## Outbox

Cider writes reminder files to `.cider/outbox/`. When you see files there:
1. Read the file to understand the reminder
2. Send the reminder content to the user via iMessage
3. Move the file to `.cider/outbox/sent/` (don't delete — serves as delivery log)

Check the outbox on every loop iteration or when vault changes are detected.
```

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Services/ReminderOutbox.swift Sources/Cider/Utilities/StoragePaths.swift Sources/Cider/Models/CiderConfig.swift
git commit -m "feat: add reminder outbox for agent-delivered iMessage notifications"
```

---

## Task 4: Extend CLI with recurrence and reminder rules

The CLI `event create` currently has no support for recurrence rules or surfacing rules. Agents need to create "pay rent on the 1st every month with 1-day and same-day reminders" from the command line.

Also: fix the birthday gap where `contact create --birthday` doesn't create the linked DateCard.

**Files:**
- Modify: `Sources/CiderCLI/CiderCLI.swift` (handleEvent function, ~line 1038)
- Modify: `Sources/CiderCLI/CiderCLI.swift` (handleContact function)
- Modify: `Sources/Cider/Services/LibraryItemEditor.swift`

- [ ] **Step 1: Add recurrence flags to `event create`**

Add these flags to the `event create` subcommand:

```
--frequency daily|weekly|monthly|yearly
--interval <N>           (default: 1)
--end-date <ISO8601>     (optional recurrence end date)
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
    let endDate = parseFlag("--end-date", from: &args).flatMap { ISO8601DateFormatter().date(from: $0) }
    card.recurrenceRule = DateCardRecurrenceRule(frequency: freq, interval: interval, endDate: endDate)
}
```

- [ ] **Step 2: Add reminder rule flags to `event create` and `event update`**

Add flag:

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

- [ ] **Step 3: Fix birthday gap in contact create/update**

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

- [ ] **Step 4: Update help text**

Add the new flags to `printUsage()`.

- [ ] **Step 5: Build and verify**

Run: `swift build -Xswiftc -warnings-as-errors 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/CiderCLI/CiderCLI.swift Sources/Cider/Services/LibraryItemEditor.swift
git commit -m "feat: CLI event create/update with recurrence rules and multi-offset reminders"
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
- `date: String` — ISO 8601 date for the first occurrence
- `frequency: String?` — "daily", "weekly", "monthly", "yearly" (nil = one-time)
- `interval: Int?` — repeat interval (default 1)
- `allDay: Bool?` — default true for reminders without specific time
- `remindMinutesBefore: [Int]?` — array of offsets, e.g. [1440, 0] for "1 day before and day-of"
- `location: String?`
- `details: String?`

The tool creates a DateCard via `DateCardStorage.shared.createDateCard(...)`, attaches recurrence and surfacing rules, then triggers reconciliation.

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
  --date $(date -v+10M +%Y-%m-%dT%H:%M:%S) \
  --remind 5 --remind 0
```

Verify:
- Two pending notifications appear in the system (5 min before and at event time)
- Notifications fire at the correct times
- Re-running the reconciler doesn't create duplicates

- [ ] **Step 2: Test recurring event scheduling**

```bash
cider-cli --vault ~/CiderTestVault event create "Daily Standup" \
  --date 2026-04-13T09:00:00 --frequency daily --remind 15
```

Verify:
- Only the next 7 days of occurrences are scheduled (bounded horizon)
- After day rollover, the window advances

- [ ] **Step 3: Test outbox flow**

Enable agent reminders in config. Create a DateCard with a reminder offset in the past-5-minutes window. Verify an outbox file appears in `.cider/outbox/`.

- [ ] **Step 4: Test birthday flow from CLI**

```bash
cider-cli --vault ~/CiderTestVault contact create "Test Person" --birthday 1990-04-15
```

Verify a linked yearly recurring DateCard is created.

- [ ] **Step 5: Commit test results / cleanup**

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
1. List files in `.cider/outbox/` (exclude `sent/` subdirectory)
2. For each `.md` file:
   a. Read the file — the body contains the reminder message to send
   b. Send the message to the user via iMessage
   c. Move the file to `.cider/outbox/sent/` as a delivery record
3. Do NOT delete outbox files — the `sent/` folder serves as a delivery ledger

### File format

```yaml
---
type: reminder
cardID: <uuid>
title: <event title>
occurrence: <ISO8601 date of the event>
minutesBefore: <offset in minutes>
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
cider-cli event create "<title>" --date <ISO8601> --frequency <daily|weekly|monthly|yearly> --remind <minutes>
```

You can specify `--remind` multiple times for multi-stage reminders (e.g., `--remind 1440 --remind 60 --remind 0` for day-before, hour-before, and at-time).
```

---

## Future work (not in this plan)

- **"Remind me again in an hour"** — Agent creates a one-time DateCard with `startAt` = now + 1 hour and `--remind 0`. The reconciler handles the rest.
- **Delivery ledger upgrade** — When agent texts become the primary channel, add a proper `(cardID, occurrence, offset) → delivered_at` table in SQLite for stricter dedup.
- **Snooze from notification** — Add a UNNotification action that creates a +1hr one-time DateCard.
- **Digest messages** — "You have 3 birthdays this week" — a daily summary outbox file composed by the reconciler.
- **Time zone handling** — `ReminderReconciler` should reconcile on `NSSystemTimeZoneDidChange` notification.
- **Launch at login** — Add `SMAppService.mainApp.register()` for login-item behavior.
