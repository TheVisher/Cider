# Contact Profile Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a richer contact profile surface with parity between the main `NSWindow` detail views and popped-out `NSPanel` floating surfaces.

**Architecture:** Add small, testable contact profile presentation helpers, then build a shared SwiftUI `ContactProfileView` consumed by both embedded and floating detail shells. Keep structured contact fields behind explicit edit mode, make the contact notes section directly editable, and resolve existing `LibraryEntityRef` links for the Related tab without building full backlink creation yet.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWindow`/`NSPanel`, existing Cider storage services, Swift Testing/XCTest.

---

## File Structure

- Create `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
  - Owns pure display helpers for tabs, essentials rows, birthday facts, and related item summaries.
  - Testable without launching windows.

- Create `Tests/CiderTests/ContactProfileModelsTests.swift`
  - Covers initials, birthday display logic, essentials summaries, and related item fallback behavior.

- Modify `Sources/Cider/Views/Contacts/ContactDetailView.swift`
  - Replace the compact contact metadata layout with the shared profile surface.
  - Keep public initializer compatible with existing callers.

- Modify `Sources/Cider/Views/Contacts/ContactEditorSheet.swift`
  - Reuse existing structured field editing for profile edit mode.
  - Only add fields if the implementation chooses a small backward-compatible `favorites` field.

- Modify `Sources/Cider/Models/ContactCard.swift`
  - Optional: add `favorites: String = ""` only if the profile cannot satisfy Favorites from existing `notes`.

- Modify `Sources/Cider/Services/VCardSerializer.swift`
  - Optional: round-trip `favorites` if added.

- Modify `Sources/Cider/Services/ContactStorage.swift`
  - Optional: persist `favorites` to SQLite and `.vcf` if added.

- Modify `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
  - Ensure floating contacts use the same `ContactDetailView`.
  - Fix floating note selection/editor readiness so note content renders reliably.

- Modify `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
  - Ensure main-window slide-out, full-panel, and page contact views still use `ContactDetailView`.

## Task 1: Contact Profile Presentation Models

**Files:**
- Create: `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
- Create: `Tests/CiderTests/ContactProfileModelsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/CiderTests/ContactProfileModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct ContactProfileModelsTests {
    @Test("initials prefer first and last name")
    func initialsPreferFirstAndLastName() {
        let contact = ContactCard(displayName: "Baine Holum")
        #expect(ContactProfileAvatar.initials(for: contact) == "BH")
    }

    @Test("initials use first two characters for single names")
    func initialsUseSingleNamePrefix() {
        let contact = ContactCard(displayName: "Baine")
        #expect(ContactProfileAvatar.initials(for: contact) == "BA")
    }

    @Test("essentials include populated contact methods and relationship")
    func essentialsIncludeImportantFields() {
        let contact = ContactCard(
            displayName: "Baine",
            relationshipLabel: "Son",
            birthday: Date(timeIntervalSince1970: 1_465_603_200),
            email: "baine@example.com",
            phone: "555-123-4567",
            address: "Home"
        )

        let rows = ContactProfileEssentials.rows(
            for: contact,
            labels: [],
            now: Date(timeIntervalSince1970: 1_777_549_201)
        )

        #expect(rows.map(\.kind).contains(.relationship))
        #expect(rows.map(\.kind).contains(.birthday))
        #expect(rows.map(\.kind).contains(.phone))
        #expect(rows.map(\.kind).contains(.email))
        #expect(rows.map(\.kind).contains(.address))
    }

    @Test("birthday facts compute age and next birthday")
    func birthdayFactsComputeAgeAndNextBirthday() {
        let birthday = Calendar.current.date(from: DateComponents(year: 2016, month: 6, day: 15))!
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let facts = ContactProfileBirthdayFacts(birthday: birthday, now: now, calendar: .current)

        #expect(facts.age == 9)
        #expect(facts.nextBirthdayComponents.month == 6)
        #expect(facts.nextBirthdayComponents.day == 15)
    }

    @Test("related summaries keep missing references visible")
    func relatedSummaryMissingFallback() {
        let id = UUID()
        let ref = LibraryEntityRef(type: .bookmark, entityID: id)
        let summary = ContactProfileRelatedItem(ref: ref, title: nil, subtitle: nil)

        #expect(summary.title == "Missing bookmark")
        #expect(summary.subtitle == id.uuidString)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter ContactProfileModelsTests
```

Expected: compile failure because `ContactProfileAvatar`, `ContactProfileEssentials`, `ContactProfileBirthdayFacts`, and `ContactProfileRelatedItem` do not exist.

- [ ] **Step 3: Add minimal presentation models**

Create `Sources/Cider/Views/Contacts/ContactProfileModels.swift`:

```swift
import Foundation

enum ContactProfileTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case birthday = "Birthday"
    case favorites = "Favorites"
    case notes = "Notes"
    case related = "Related"

    var id: String { rawValue }
}

enum ContactProfileAvatar {
    static func initials(for contact: ContactCard) -> String {
        let parts = contact.displayName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }

        return String(contact.displayName.prefix(2)).uppercased()
    }
}

struct ContactProfileEssentialRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case relationship
        case birthday
        case phone
        case email
        case address
        case labels
    }

    let id: String
    let kind: Kind
    let symbol: String
    let text: String
}

enum ContactProfileEssentials {
    static func rows(
        for contact: ContactCard,
        labels: [CardLabel],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ContactProfileEssentialRow] {
        var rows: [ContactProfileEssentialRow] = []

        if !contact.relationshipLabel.isEmpty {
            rows.append(.init(id: "relationship", kind: .relationship, symbol: "heart", text: contact.relationshipLabel))
        }

        if let birthday = contact.birthday {
            let facts = ContactProfileBirthdayFacts(birthday: birthday, now: now, calendar: calendar)
            rows.append(.init(
                id: "birthday",
                kind: .birthday,
                symbol: "gift",
                text: "\(birthday.formatted(.dateTime.month(.abbreviated).day().year())) · \(facts.age) years old"
            ))
        }

        if !contact.phone.isEmpty {
            rows.append(.init(id: "phone", kind: .phone, symbol: "phone", text: contact.phone))
        }

        if !contact.email.isEmpty {
            rows.append(.init(id: "email", kind: .email, symbol: "envelope", text: contact.email))
        }

        if !contact.address.isEmpty {
            rows.append(.init(id: "address", kind: .address, symbol: "mappin.and.ellipse", text: contact.address))
        }

        let matchingLabels = labels.filter { contact.labelIDs.contains($0.id) }
        if !matchingLabels.isEmpty {
            rows.append(.init(
                id: "labels",
                kind: .labels,
                symbol: "tag",
                text: matchingLabels.map(\.name).joined(separator: ", ")
            ))
        }

        return rows
    }
}

struct ContactProfileBirthdayFacts: Equatable {
    let age: Int
    let nextBirthday: Date
    let nextBirthdayComponents: DateComponents

    init(birthday: Date, now: Date = Date(), calendar: Calendar = .current) {
        let birthdayComponents = calendar.dateComponents([.month, .day], from: birthday)
        let currentYear = calendar.component(.year, from: now)
        let birthYear = calendar.component(.year, from: birthday)

        let birthdayThisYear = calendar.date(from: DateComponents(
            year: currentYear,
            month: birthdayComponents.month,
            day: birthdayComponents.day
        )) ?? birthday

        let nextYear = birthdayThisYear < calendar.startOfDay(for: now) ? currentYear + 1 : currentYear
        let next = calendar.date(from: DateComponents(
            year: nextYear,
            month: birthdayComponents.month,
            day: birthdayComponents.day
        )) ?? birthdayThisYear

        let hadBirthdayThisYear = birthdayThisYear <= now
        self.age = max(0, currentYear - birthYear - (hadBirthdayThisYear ? 0 : 1))
        self.nextBirthday = next
        self.nextBirthdayComponents = calendar.dateComponents([.month, .day], from: next)
    }
}

struct ContactProfileRelatedItem: Identifiable, Equatable {
    let ref: LibraryEntityRef
    let title: String
    let subtitle: String

    var id: String { ref.id }

    init(ref: LibraryEntityRef, title: String?, subtitle: String?) {
        self.ref = ref
        self.title = title?.isEmpty == false ? title! : "Missing \(ref.type.rawValue)"
        self.subtitle = subtitle?.isEmpty == false ? subtitle! : ref.entityID.uuidString
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter ContactProfileModelsTests
```

Expected: all tests pass.

## Task 2: Shared Contact Profile View

**Files:**
- Modify: `Sources/Cider/Views/Contacts/ContactDetailView.swift`

- [ ] **Step 1: Replace compact layout with shared profile structure**

Modify `ContactDetailView` so it owns:

```swift
@State private var selectedTab: ContactProfileTab = .overview
@State private var isEditingProfile = false
@State private var draftNotes = ""
@State private var isEssentialsExpanded = true
```

Keep `ContactDetailView(contact:onEdit:onDismiss:)` unchanged for callers. Render:

```swift
VStack(alignment: .leading, spacing: 0) {
    profileHeader
    tabBar
    Divider()
    GeometryReader { proxy in
        if proxy.size.width >= 620 {
            HStack(alignment: .top, spacing: 0) {
                tabContent
                Divider()
                essentialsRail
                    .frame(width: 240)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    collapsibleEssentials
                    tabContent
                }
                .padding(Spacing.md)
            }
        }
    }
}
.onAppear { draftNotes = contact.notes }
.onChange(of: contact.id) { _, _ in draftNotes = contact.notes }
.onChange(of: contact.notes) { _, value in draftNotes = value }
```

- [ ] **Step 2: Add view-mode tab content**

Implement `tabContent` cases:

```swift
switch selectedTab {
case .overview:
    ContactProfileOverviewSection(contact: contact)
case .birthday:
    ContactProfileBirthdaySection(contact: contact)
case .favorites:
    ContactProfileFavoritesSection(contact: contact)
case .notes:
    ContactProfileNotesSection(contact: contact, draftNotes: $draftNotes, onSave: saveNotes)
case .related:
    ContactProfileRelatedSection(contact: contact)
}
```

Keep these as private subviews in `ContactDetailView.swift` for the first pass unless the file becomes unwieldy.

- [ ] **Step 3: Add notes save helper**

Add:

```swift
private func saveNotes() {
    var updated = contact
    updated.notes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = ContactStorage.shared.updateContact(updated)
}
```

Call it from notes editor `onSubmit`/focus loss where practical, and from `onDisappear`.

- [ ] **Step 4: Run contact profile tests**

Run:

```bash
swift test --filter ContactProfileModelsTests
```

Expected: pass.

## Task 3: Related Items Section

**Files:**
- Modify: `Sources/Cider/Views/Contacts/ContactDetailView.swift`
- Modify: `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
- Test: `Tests/CiderTests/ContactProfileModelsTests.swift`

- [ ] **Step 1: Add pure title fallback tests**

Extend `ContactProfileModelsTests`:

```swift
@Test("related missing labels are human readable")
func relatedMissingLabelsAreHumanReadable() {
    let bookmark = ContactProfileRelatedItem(ref: LibraryEntityRef(type: .bookmark, entityID: UUID()), title: nil, subtitle: nil)
    let date = ContactProfileRelatedItem(ref: LibraryEntityRef(type: .dateCard, entityID: UUID()), title: nil, subtitle: nil)
    #expect(bookmark.title == "Missing bookmark")
    #expect(date.title == "Missing date card")
}
```

- [ ] **Step 2: Update display labels**

Add to `ContactProfileModels.swift`:

```swift
extension LibraryEntityType {
    var contactProfileDisplayName: String {
        switch self {
        case .bookmark: "bookmark"
        case .note: "note"
        case .dateCard: "date card"
        case .contact: "contact"
        case .todo: "todo"
        case .vaultFile: "file"
        case .externalFile: "file"
        case .session: "session"
        }
    }
}
```

Change missing title to:

```swift
self.title = title?.isEmpty == false ? title! : "Missing \(ref.type.contactProfileDisplayName)"
```

- [ ] **Step 3: Resolve linked refs in the view**

In `ContactProfileRelatedSection`, map `contact.linkedEntities` through existing storages:

```swift
private var relatedItems: [ContactProfileRelatedItem] {
    contact.linkedEntities.map { ref in
        switch ref.type {
        case .bookmark:
            let bookmark = VaultBookmarkService.shared.bookmarks.first { $0.id == ref.entityID }
            return ContactProfileRelatedItem(ref: ref, title: bookmark?.title, subtitle: bookmark?.urlString)
        case .note:
            let note = NotesStorage.shared.notes.first { $0.id == ref.entityID }
            return ContactProfileRelatedItem(ref: ref, title: note?.title, subtitle: "Note")
        case .dateCard:
            let card = DateCardStorage.shared.dateCard(for: ref.entityID)
            return ContactProfileRelatedItem(ref: ref, title: card?.title, subtitle: card?.startAt.formatted(.dateTime.month(.abbreviated).day()))
        case .contact:
            let contact = ContactStorage.shared.contact(for: ref.entityID)
            return ContactProfileRelatedItem(ref: ref, title: contact?.displayName, subtitle: contact?.relationshipLabel)
        case .todo:
            let todo = TodoCardStorage.shared.todoCard(for: ref.entityID)
            return ContactProfileRelatedItem(ref: ref, title: todo?.title, subtitle: "Todo")
        case .vaultFile:
            let file = VaultFileStorage.shared.files.first { $0.id == ref.entityID }
            return ContactProfileRelatedItem(ref: ref, title: file?.filename, subtitle: file?.relativePath)
        case .externalFile, .session:
            return ContactProfileRelatedItem(ref: ref, title: nil, subtitle: nil)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter ContactProfileModelsTests
```

Expected: pass.

## Task 4: Main Window And Floating Panel Parity

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`

- [ ] **Step 1: Verify all embedded contact paths call `ContactDetailView`**

Confirm these paths use the same `ContactDetailView`:

- `genericDetailSlideOutContainer`
- `genericDetailFullPanelOverlay`
- `genericDetailPageView`
- `FloatingContactDetail`

- [ ] **Step 2: Remove any duplicated contact-only layout in floating views**

If `FloatingContactDetail` wraps contact content differently, keep only the shared `ContactDetailView(contact:onEdit:onDismiss:)` body inside `GenericItemDetailPanel`.

- [ ] **Step 3: Preserve shell-specific controls**

Main window keeps:

```swift
onFloat: floatContactDetail
onClose: closeGenericDetail
onModeChange: changeDetailViewMode
```

Floating panel keeps:

```swift
FloatingReanchorButton(surface: surface)
onClose: { dock(surface, action: onDock) }
```

- [ ] **Step 4: Build check**

Run:

```bash
swift build -Xswiftc -warnings-as-errors
```

Expected: build succeeds, or compile errors are limited to contact profile integration and fixed in place.

## Task 5: Floating Note Rendering Reliability

**Files:**
- Modify: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
- Modify: `Sources/Cider/ViewModels/NotesViewModel.swift` only if a small readiness hook is required

- [ ] **Step 1: Add deterministic sync after editor readiness**

In `FloatingNoteDetail`, keep `syncSelectedNote()` on appear, but also trigger it after the editor is likely mounted:

```swift
.task(id: note.id) {
    syncSelectedNote()
    try? await Task.sleep(for: .milliseconds(150))
    syncSelectedNote(forcePush: true)
}
```

Change helper to:

```swift
private func syncSelectedNote(forcePush: Bool = false) {
    if viewModel.selectedNote?.id != note.id {
        viewModel.selectNote(note)
        return
    }

    if forcePush {
        viewModel.pushCurrentContentToEditorIfReady()
    }
}
```

- [ ] **Step 2: Add a small public view-model hook if needed**

If `NotesViewModel` has no safe current-content push method, add:

```swift
func pushCurrentContentToEditorIfReady() {
    guard let selectedNote else { return }
    pushContentToEditor(selectedNote.content)
}
```

Keep it `@MainActor` with the rest of `NotesViewModel`.

- [ ] **Step 3: Run note-related tests**

Run:

```bash
swift test --filter NoteEditorModeTests
swift test --filter NotesMarkdownPathCodecTests
```

Expected: pass.

## Task 6: Verification

**Files:**
- Modify only files needed to fix failures.

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter ContactProfileModelsTests
swift test --filter ContactSQLiteTests
swift test --filter CiderFloatableSurfaceTests
swift test --filter CiderSurfaceRecallCoordinatorTests
```

Expected: all pass.

- [ ] **Step 2: Run build**

Run:

```bash
swift build -Xswiftc -warnings-as-errors
```

Expected: build succeeds.

- [ ] **Step 3: Manual QA**

Launch the app and verify:

- contact profile opens from main-window folder/card views
- contact profile opens from floating panel
- `Overview`, `Birthday`, `Favorites`, `Notes`, and `Related` tabs work in both
- Essentials remains visible or collapses according to width
- editing notes persists and refreshes the contact
- profile edit opens the existing contact editor and saves structured fields
- linked birthday date cards appear in `Related`
- popped-out note content renders after opening a note surface

## Self-Review

- Spec coverage: profile tabs, Essentials, notes editing, related items, edit mode, main/floating parity, and floating note reliability are each covered by tasks.
- Completion scan: no `TBD` markers or undefined implementation gaps remain.
- Type consistency: `ContactProfileTab`, `ContactProfileAvatar`, `ContactProfileEssentials`, `ContactProfileBirthdayFacts`, and `ContactProfileRelatedItem` are introduced before use.
