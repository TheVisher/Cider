# Universal Metadata Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a universal metadata inspector rail to Cider detail surfaces, with contact editing moving into the rail and backlinks visible across supported card types.

**Architecture:** Extract common metadata models and reusable SwiftUI rail sections, then extend `GenericItemDetailPanel` so non-bookmark details can show the same `i` toggle and right-side inspector as bookmarks. Contacts get a contact-specific inspector/editor; notes, todos, date cards, and vault files get read-mostly metadata rails that preserve their primary body workflows.

**Tech Stack:** Swift, SwiftUI, AppKit panels, Cider SQLite-backed storage services, Swift Testing, `xcodebuild`, `cider-cli`.

---

## File Structure

- Create `Sources/Cider/Views/Shared/ItemMetadataInspectorModels.swift`
  - Pure metadata section and row models used by tests and SwiftUI views.
  - Helpers for date formatting, empty-section filtering, and related-item conversion.
- Create `Sources/Cider/Views/Shared/ItemMetadataInspectorView.swift`
  - Reusable rail shell, section headers, linked-item rows, labels rows, info footer, and shared metadata toggle button.
- Modify `Sources/Cider/Views/Shared/GenericItemDetailPanel.swift`
  - Add optional metadata rail support, shared `i` button, and right-side rail compression.
- Modify `Sources/Cider/Views/Shared/DetailSlideOutView.swift`
  - Reuse the shared metadata toggle button for bookmark details.
- Modify `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
  - Remove `Notes` and `Related` from contact body tabs.
  - Add contact rail helper models for notes preview and custom-field editing.
- Modify `Sources/Cider/Views/Contacts/ContactDetailView.swift`
  - Keep the readable contact body focused on Overview, Birthday, and Favorites.
  - Remove direct note editing and related-list UI from the body.
- Create `Sources/Cider/Views/Contacts/ContactMetadataInspectorView.swift`
  - Contact-specific inspector and edit panel for essentials, custom fields, metadata notes, links, labels, and info.
- Modify `Sources/Cider/Views/CiderPanelView.swift`
  - Add rail visibility state for generic item details.
- Modify `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
  - Wire metadata rails into main-window slide-out, full-panel, and page detail surfaces.
- Modify `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`
  - Wire metadata rails into contact, note, todo, date-card, and bookmark floating `NSPanel` surfaces.
- Modify `Sources/Cider/Views/Notes/InlineNoteEditorView.swift`
  - Add backlinks/info sections to note metadata without moving Markdown formatting controls.
- Create or modify tests:
  - `Tests/CiderTests/ItemMetadataInspectorModelsTests.swift`
  - `Tests/CiderTests/ContactProfileModelsTests.swift`
  - `Tests/CiderTests/ContactCustomFieldsTests.swift`
  - `Tests/CiderTests/ContactCLIHelpTextTests.swift`
  - `Tests/CiderTests/ItemLinkServiceTests.swift`

---

### Task 1: Add Pure Metadata Inspector Models

**Files:**
- Create: `Sources/Cider/Views/Shared/ItemMetadataInspectorModels.swift`
- Create: `Tests/CiderTests/ItemMetadataInspectorModelsTests.swift`

- [ ] **Step 1: Write failing tests for metadata section filtering and info rows**

Create `Tests/CiderTests/ItemMetadataInspectorModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import Cider

struct ItemMetadataInspectorModelsTests {
    @Test("empty sections without actions are omitted")
    func emptySectionsWithoutActionsAreOmitted() {
        let sections = [
            ItemMetadataSection(id: "linked", title: "Linked", rows: []),
            ItemMetadataSection(id: "notes", title: "Notes", rows: [], emptyActionTitle: "Add Note"),
            ItemMetadataSection(id: "info", title: "Info", rows: [
                ItemMetadataRow(id: "type", symbol: "info.circle", title: "Type", value: "Contact")
            ])
        ]

        #expect(ItemMetadataSection.visibleSections(from: sections).map(\.id) == ["notes", "info"])
    }

    @Test("related summaries become clickable metadata rows")
    func relatedSummariesBecomeRows() {
        let ref = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let summary = ItemLinkSummary(ref: ref, title: "Gift idea", subtitle: "Bookmark", symbol: "bookmark")

        let row = ItemMetadataRow.related(summary)

        #expect(row.id == "related-\(ref.type.rawValue)-\(ref.entityID.uuidString)")
        #expect(row.symbol == "bookmark")
        #expect(row.title == "Gift idea")
        #expect(row.value == "Bookmark")
        #expect(row.ref == ref)
    }

    @Test("info rows use stable created updated type order")
    func infoRowsUseStableOrder() {
        let created = Date(timeIntervalSince1970: 100)
        let updated = Date(timeIntervalSince1970: 200)

        let rows = ItemMetadataInfoRows.rows(
            createdAt: created,
            updatedAt: updated,
            typeLabel: "Contact",
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(rows.map(\.id) == ["created", "updated", "type"])
        #expect(rows[2].value == "Contact")
    }
}
```

- [ ] **Step 2: Run the new test file and confirm it fails**

Run:

```bash
swift test --filter ItemMetadataInspectorModelsTests
```

Expected: fail because `ItemMetadataSection`, `ItemMetadataRow`, and `ItemMetadataInfoRows` do not exist.

- [ ] **Step 3: Add the pure metadata models**

Create `Sources/Cider/Views/Shared/ItemMetadataInspectorModels.swift`:

```swift
import Foundation

struct ItemMetadataRow: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let value: String
    let ref: LibraryEntityRef?

    init(id: String, symbol: String, title: String, value: String = "", ref: LibraryEntityRef? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.value = value
        self.ref = ref
    }

    static func related(_ summary: ItemLinkSummary) -> ItemMetadataRow {
        ItemMetadataRow(
            id: "related-\(summary.ref.type.rawValue)-\(summary.ref.entityID.uuidString)",
            symbol: summary.symbol,
            title: summary.title,
            value: summary.subtitle,
            ref: summary.ref
        )
    }
}

struct ItemMetadataSection: Identifiable, Equatable {
    let id: String
    let title: String
    var rows: [ItemMetadataRow]
    var emptyActionTitle: String?

    static func visibleSections(from sections: [ItemMetadataSection]) -> [ItemMetadataSection] {
        sections.filter { !$0.rows.isEmpty || $0.emptyActionTitle != nil }
    }
}

enum ItemMetadataInfoRows {
    static func rows(
        createdAt: Date,
        updatedAt: Date,
        typeLabel: String,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [ItemMetadataRow] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return [
            ItemMetadataRow(id: "created", symbol: "calendar.badge.plus", title: "Created", value: formatter.string(from: createdAt)),
            ItemMetadataRow(id: "updated", symbol: "clock", title: "Updated", value: formatter.string(from: updatedAt)),
            ItemMetadataRow(id: "type", symbol: "info.circle", title: "Type", value: typeLabel)
        ]
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:

```bash
swift test --filter ItemMetadataInspectorModelsTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/Shared/ItemMetadataInspectorModels.swift Tests/CiderTests/ItemMetadataInspectorModelsTests.swift
git commit -m "Add metadata inspector model helpers"
```

---

### Task 2: Add Shared Metadata Rail UI And Generic Panel Support

**Files:**
- Create: `Sources/Cider/Views/Shared/ItemMetadataInspectorView.swift`
- Modify: `Sources/Cider/Views/Shared/GenericItemDetailPanel.swift`
- Modify: `Sources/Cider/Views/Shared/DetailSlideOutView.swift`

- [ ] **Step 1: Add shared rail views**

Create `Sources/Cider/Views/Shared/ItemMetadataInspectorView.swift`:

```swift
import SwiftUI

struct ItemMetadataToggleButton: View {
    @Binding var isVisible: Bool
    var helpVisible: String = "Hide metadata"
    var helpHidden: String = "Show metadata"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isVisible.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: isVisible ? "info.circle.fill" : "info.circle")
                        .font(CiderFont.toolbarIcon)
                        .foregroundColor(isVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(isVisible ? helpVisible : helpHidden)
    }
}

struct ItemMetadataInspectorView<Content: View>: View {
    var width: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
    }
}

struct ItemMetadataSectionView<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
        .padding(.vertical, Spacing.md)
    }
}

struct ItemMetadataRowsView: View {
    let rows: [ItemMetadataRow]
    var onOpenRef: ((LibraryEntityRef) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(rows) { row in
                if let ref = row.ref, let onOpenRef {
                    Button {
                        onOpenRef(ref)
                    } label: {
                        metadataRow(row)
                    }
                    .buttonStyle(.plain)
                } else {
                    metadataRow(row)
                }
            }
        }
    }

    private func metadataRow(_ row: ItemMetadataRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: row.symbol)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(row.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                if !row.value.isEmpty {
                    Text(row.value)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Extend `GenericItemDetailPanel` to accept metadata**

Modify `Sources/Cider/Views/Shared/GenericItemDetailPanel.swift` so the type has a fourth generic and metadata configuration:

```swift
struct GenericItemDetailPanel<Content: View, ToolbarExtra: View, TrailingExtra: View, Metadata: View>: View {
    var title: String
    var detailViewMode: DetailViewMode
    var width: CGFloat = 0
    var maxWidth: CGFloat = 0
    var showDragHandle: Bool = true
    var showTitle: Bool = true
    var scrollsContent: Bool = true
    var onRenameTitle: ((String) -> Void)? = nil
    var isEditingTitle: Binding<Bool>? = nil
    var metadataVisible: Binding<Bool>?
    var metadataWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    var onResize: (CGFloat) -> Void = { _ in }
    var onFloat: (() -> Void)? = nil
    var onClose: () -> Void
    var onModeChange: (DetailViewMode) -> Void
    @ViewBuilder var toolbarExtra: () -> ToolbarExtra
    @ViewBuilder var trailingExtra: () -> TrailingExtra
    @ViewBuilder var metadata: () -> Metadata
    @ViewBuilder var content: () -> Content
}
```

In the toolbar, render the toggle immediately before `trailingExtra()`:

```swift
if let metadataVisible {
    ItemMetadataToggleButton(isVisible: metadataVisible)
}

trailingExtra()
```

In the body content area, replace the current single content branch with:

```swift
HStack(alignment: .top, spacing: 0) {
    Group {
        if scrollsContent {
            ScrollView {
                content()
                    .padding(Spacing.md)
            }
            .scrollIndicators(.hidden)
        } else {
            content()
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if metadataVisible?.wrappedValue == true {
        metadata()
            .frame(width: metadataWidth)
            .transition(
                .detailSlideOutSidebar(
                    style: DetailSlideOutMotionPolicy.sidebarTransitionStyle()
                )
            )
    }
}
.frame(maxHeight: .infinity)
```

Update all convenience initializers to set:

```swift
self.metadataVisible = nil
self.metadataWidth = BookmarksDesign.detailsSidebarFixedWidth
self.metadata = { EmptyView() }
```

Add a new convenience initializer for metadata callers:

```swift
extension GenericItemDetailPanel where ToolbarExtra == EmptyView {
    init(
        title: String,
        detailViewMode: DetailViewMode,
        width: CGFloat = 0,
        maxWidth: CGFloat = 0,
        showDragHandle: Bool = true,
        showTitle: Bool = true,
        scrollsContent: Bool = true,
        metadataVisible: Binding<Bool>,
        metadataWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth,
        onResize: @escaping (CGFloat) -> Void = { _ in },
        onFloat: (() -> Void)? = nil,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (DetailViewMode) -> Void,
        @ViewBuilder trailingExtra: @escaping () -> TrailingExtra,
        @ViewBuilder metadata: @escaping () -> Metadata,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detailViewMode = detailViewMode
        self.width = width
        self.maxWidth = maxWidth
        self.showDragHandle = showDragHandle
        self.showTitle = showTitle
        self.scrollsContent = scrollsContent
        self.metadataVisible = metadataVisible
        self.metadataWidth = metadataWidth
        self.onResize = onResize
        self.onFloat = onFloat
        self.onClose = onClose
        self.onModeChange = onModeChange
        self.toolbarExtra = { EmptyView() }
        self.trailingExtra = trailingExtra
        self.metadata = metadata
        self.content = content
    }
}
```

- [ ] **Step 3: Replace bookmark toggle button duplication**

In `Sources/Cider/Views/Shared/DetailSlideOutView.swift`, replace the hand-built metadata toggle in `toolbar` and `BookmarkPageToolbar` with:

```swift
ItemMetadataToggleButton(isVisible: $isMetadataVisible)
```

- [ ] **Step 4: Build to catch generic initializer regressions**

Run:

```bash
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Views/Shared/ItemMetadataInspectorView.swift Sources/Cider/Views/Shared/GenericItemDetailPanel.swift Sources/Cider/Views/Shared/DetailSlideOutView.swift
git commit -m "Add shared metadata rail shell"
```

---

### Task 3: Move Contact Notes And Related Out Of The Body

**Files:**
- Modify: `Sources/Cider/Views/Contacts/ContactProfileModels.swift`
- Modify: `Sources/Cider/Views/Contacts/ContactDetailView.swift`
- Modify: `Tests/CiderTests/ContactProfileModelsTests.swift`

- [ ] **Step 1: Update failing tab tests**

Add this test to `Tests/CiderTests/ContactProfileModelsTests.swift`:

```swift
@Test("contact profile tabs only include person profile sections")
func contactProfileTabsOnlyIncludePersonProfileSections() {
    #expect(ContactProfileTab.allCases == [.overview, .birthday, .favorites])
}
```

Replace the existing `essentialsRailHidesOnBirthdayTab` test with:

```swift
@Test("essentials can show for every remaining contact profile tab")
func essentialsCanShowForEveryRemainingContactTab() {
    #expect(ContactProfileEssentials.shouldShowRail(for: .overview))
    #expect(ContactProfileEssentials.shouldShowRail(for: .birthday))
    #expect(ContactProfileEssentials.shouldShowRail(for: .favorites))
}
```

- [ ] **Step 2: Run the contact profile tests and confirm they fail**

Run:

```bash
swift test --filter ContactProfileModelsTests
```

Expected: fail because `ContactProfileTab` still includes `notes` and `related`, and birthday currently hides essentials.

- [ ] **Step 3: Update contact profile tab model**

In `Sources/Cider/Views/Contacts/ContactProfileModels.swift`, change the enum to:

```swift
enum ContactProfileTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case birthday = "Birthday"
    case favorites = "Favorites"

    var id: String { rawValue }
}
```

Change `ContactProfileEssentials.shouldShowRail(for:)` to:

```swift
static func shouldShowRail(for tab: ContactProfileTab) -> Bool {
    true
}
```

- [ ] **Step 4: Remove body notes and related state from contact detail**

In `Sources/Cider/Views/Contacts/ContactDetailView.swift`:

Remove these properties:

```swift
var onOpenRelated: ((LibraryEntityRef) -> Void)? = nil
@State private var draftNotes = ""
@State private var hasUnsavedNotes = false
@State private var isEditingNotes = false
```

Replace `tabContent` with:

```swift
@ViewBuilder
private var tabContent: some View {
    Group {
        switch selectedTab {
        case .overview:
            ContactProfileOverviewSection(contact: contact)
        case .birthday:
            ContactProfileBirthdaySection(contact: contact)
        case .favorites:
            ContactProfileFavoritesSection(contact: contact)
        }
    }
    .frame(minWidth: 280, maxWidth: .infinity, alignment: .topLeading)
}
```

Remove `ContactProfileNotesSection`, `ContactProfileRelatedSection`, `saveNotesIfNeeded()`, and all `.onAppear`, `.onChange`, and `.onDisappear` handlers that only synchronize notes.

In the Edit and Done button actions, remove `saveNotesIfNeeded()` calls:

```swift
Button("Edit") {
    onEdit()
}
```

```swift
Button("Done") {
    onDismiss()
}
```

- [ ] **Step 5: Run the contact profile tests and build**

Run:

```bash
swift test --filter ContactProfileModelsTests
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Contacts/ContactProfileModels.swift Sources/Cider/Views/Contacts/ContactDetailView.swift Tests/CiderTests/ContactProfileModelsTests.swift
git commit -m "Keep contact body focused on profile tabs"
```

---

### Task 4: Add Contact Metadata Inspector And Rail Editing

**Files:**
- Create: `Sources/Cider/Views/Contacts/ContactMetadataInspectorView.swift`
- Modify: `Tests/CiderTests/ContactCustomFieldsTests.swift`

- [ ] **Step 1: Add pure edit helper tests**

Append to `Tests/CiderTests/ContactCustomFieldsTests.swift`:

```swift
@Test("contact metadata draft can add update and delete fields")
func metadataDraftCanAddUpdateAndDeleteFields() {
    var draft = ContactMetadataDraft(contact: ContactCard(displayName: "Baine"))

    let id = draft.addField(section: "Favorites", label: "Color", value: "Black", kind: .text, isPinned: true)
    draft.updateField(id: id, section: "Favorites", label: "Favorite Color", value: "Black", kind: .text, isPinned: true)
    draft.deleteField(id: id)

    #expect(draft.customFields.isEmpty)
}

@Test("contact metadata draft applies notes and known fields")
func metadataDraftAppliesNotesAndKnownFields() {
    var draft = ContactMetadataDraft(contact: ContactCard(displayName: "Baine"))
    draft.displayName = "Baine Holum"
    draft.relationshipLabel = "Son"
    draft.notes = "# Baine\n\nLikes games."

    let updated = draft.apply(to: ContactCard(displayName: "Baine"))

    #expect(updated.displayName == "Baine Holum")
    #expect(updated.relationshipLabel == "Son")
    #expect(updated.notes == "# Baine\n\nLikes games.")
}
```

- [ ] **Step 2: Run the custom field tests and confirm they fail**

Run:

```bash
swift test --filter ContactCustomFieldsTests
```

Expected: fail because `ContactMetadataDraft` does not exist.

- [ ] **Step 3: Create contact metadata draft and inspector**

Create `Sources/Cider/Views/Contacts/ContactMetadataInspectorView.swift` with this structure:

```swift
import SwiftUI

struct ContactMetadataDraft: Equatable {
    var displayName: String
    var relationshipLabel: String
    var birthday: Date?
    var notes: String
    var email: String
    var phone: String
    var address: String
    var labelIDs: [UUID]
    var customFields: [ContactCustomField]

    init(contact: ContactCard) {
        displayName = contact.displayName
        relationshipLabel = contact.relationshipLabel
        birthday = contact.birthday
        notes = contact.notes
        email = contact.email
        phone = contact.phone
        address = contact.address
        labelIDs = contact.labelIDs
        customFields = contact.customFields
    }

    mutating func addField(section: String, label: String, value: String, kind: ContactCustomFieldKind, isPinned: Bool) -> UUID {
        let field = ContactCustomField(section: section, label: label, value: value, kind: kind, isPinned: isPinned)
        customFields.append(field)
        return field.id
    }

    mutating func updateField(id: UUID, section: String, label: String, value: String, kind: ContactCustomFieldKind, isPinned: Bool) {
        guard let index = customFields.firstIndex(where: { $0.id == id }) else { return }
        customFields[index].section = section
        customFields[index].label = label
        customFields[index].value = value
        customFields[index].kind = kind
        customFields[index].isPinned = isPinned
    }

    mutating func deleteField(id: UUID) {
        customFields.removeAll { $0.id == id }
    }

    func apply(to contact: ContactCard) -> ContactCard {
        var updated = contact
        updated.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.relationshipLabel = relationshipLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.birthday = birthday
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.labelIDs = labelIDs
        updated.customFields = customFields.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return updated
    }
}
```

In the same file, add `ContactMetadataInspectorView`:

```swift
struct ContactMetadataInspectorView: View {
    let contact: ContactCard
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var draft: ContactMetadataDraft
    @State private var isEditing = false
    @State private var isEssentialsExpanded = true
    @State private var isLinkedExpanded = true
    @State private var isNotesExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isInfoExpanded = true
    @State private var saveError: String?

    init(contact: ContactCard, onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil) {
        self.contact = contact
        self.onOpenLinkedRef = onOpenLinkedRef
        _draft = State(initialValue: ContactMetadataDraft(contact: contact))
    }

    var body: some View {
        ItemMetadataInspectorView {
            titleSection
            Divider().background(CiderColors.separator)
            essentialsSection
            Divider().background(CiderColors.separator)
            linkedSection
            Divider().background(CiderColors.separator)
            notesSection
            Divider().background(CiderColors.separator)
            labelsSection
            Divider().background(CiderColors.separator)
            infoSection
            editFooter
        }
        .onChange(of: contact.id) { _, _ in
            draft = ContactMetadataDraft(contact: contact)
            isEditing = false
            saveError = nil
        }
    }
}
```

Add these minimum private sections in the same file so the rail has working read and edit flows:

```swift
private var titleSection: some View {
    Group {
        if isEditing {
            TextField("Name", text: $draft.displayName)
                .textFieldStyle(.plain)
                .font(CiderFont.bodySemibold)
                .padding(Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(CiderColors.surfaceInput))
        } else {
            Text(contact.displayName)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
        }
    }
    .padding(.bottom, Spacing.md)
}

private var essentialsSection: some View {
    ItemMetadataSectionView(title: "Essentials", isExpanded: $isEssentialsExpanded) {
        if isEditing {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextField("Relationship", text: $draft.relationshipLabel)
                TextField("Email", text: $draft.email)
                TextField("Phone", text: $draft.phone)
                TextField("Address", text: $draft.address, axis: .vertical)
            }
            .textFieldStyle(.roundedBorder)
        } else {
            ItemMetadataRowsView(rows: ContactProfileEssentials.rows(for: contact, labels: labelStorage.labels).map {
                ItemMetadataRow(id: $0.id, symbol: $0.symbol, title: $0.text)
            })
        }
    }
}

private var linkedSection: some View {
    ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
        if relatedRows.isEmpty {
            Text("No linked items.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.quaternary)
        } else {
            ItemMetadataRowsView(rows: relatedRows, onOpenRef: onOpenLinkedRef)
        }
    }
}

private var notesSection: some View {
    ItemMetadataSectionView(title: "Notes", isExpanded: $isNotesExpanded) {
        if isEditing {
            TextEditor(text: $draft.notes)
                .font(CiderFont.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(Spacing.xs)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(CiderColors.surfaceSubtle))
        } else {
            let lines = ContactProfileNotePreview.lines(from: contact.notes, contact: contact, includeRepresentedFacts: true)
            if lines.isEmpty {
                Text("No notes saved.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                    }
                }
            }
        }
    }
}

private var labelsSection: some View {
    ItemMetadataSectionView(title: "Labels", isExpanded: $isLabelsExpanded) {
        let labels = labelStorage.labels.filter { contact.labelIDs.contains($0.id) }
        if labels.isEmpty {
            Text("No labels.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.quaternary)
        } else {
            ItemMetadataRowsView(rows: labels.map {
                ItemMetadataRow(id: "label-\($0.id.uuidString)", symbol: "tag", title: $0.name)
            })
        }
    }
}

private var infoSection: some View {
    ItemMetadataSectionView(title: "Info", isExpanded: $isInfoExpanded) {
        ItemMetadataRowsView(rows: ItemMetadataInfoRows.rows(
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt,
            typeLabel: "Contact"
        ))
    }
}

private var editFooter: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        if let saveError {
            Text(saveError)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.destructive)
        }
        HStack {
            Spacer(minLength: 0)
            if isEditing {
                Button("Cancel") {
                    draft = ContactMetadataDraft(contact: contact)
                    isEditing = false
                    saveError = nil
                }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Edit") { isEditing = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    .padding(.top, Spacing.md)
}
```

Use this save method:

```swift
private func save() {
    let updated = draft.apply(to: contact)
    guard !updated.displayName.isEmpty else {
        saveError = "Name is required."
        return
    }
    guard ContactStorage.shared.updateContact(updated) else {
        saveError = "Could not save contact."
        return
    }
    isEditing = false
    saveError = nil
}
```

Use this related rows helper:

```swift
private var relatedRows: [ItemMetadataRow] {
    let contactRef = LibraryEntityRef(type: .contact, entityID: contact.id)
    let refs = (try? ItemLinkService.shared.relatedRefs(for: contactRef)) ?? []
    return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
}
```

- [ ] **Step 4: Run contact field tests**

Run:

```bash
swift test --filter ContactCustomFieldsTests
```

Expected: pass.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/Contacts/ContactMetadataInspectorView.swift Tests/CiderTests/ContactCustomFieldsTests.swift
git commit -m "Add contact metadata inspector editor"
```

---

### Task 5: Wire Contact Metadata Rail Into Main Window And Floating Panels

**Files:**
- Modify: `Sources/Cider/Views/CiderPanelView.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`

- [ ] **Step 1: Add main-window generic metadata state**

In `Sources/Cider/Views/CiderPanelView.swift`, near `bookmarkMetadataVisible`, add:

```swift
@State var genericMetadataVisible: Bool = true
```

- [ ] **Step 2: Wire contact slide-out, full-panel, and page views**

In every `GenericItemDetailPanel` call that renders `ContactDetailView`, pass metadata parameters:

```swift
metadataVisible: $genericMetadataVisible,
metadata: {
    ContactMetadataInspectorView(contact: contact, onOpenLinkedRef: openLinkedRef)
}
```

Remove the deleted `onOpenRelated:` argument from `ContactDetailView` calls:

```swift
ContactDetailView(
    contact: contact,
    onEdit: {
        genericMetadataVisible = true
    },
    onDismiss: closeGenericDetail
)
```

For existing Edit buttons inside the contact body, opening the rail is the edit affordance. Do not reopen `ContactEditorSheet` from the contact body after this task.

- [ ] **Step 3: Reset the rail when selecting a new generic item**

In `Sources/Cider/Views/CiderPanelView+DetailManagement.swift`, inside `openDateCardDetail`, `openContactDetail`, `openTodoDetail`, and `openVaultFileDetail`, add:

```swift
genericMetadataVisible = true
```

- [ ] **Step 4: Wire floating contact panels**

In `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`, update `FloatingContactDetail`:

```swift
@State private var isMetadataVisible = true
```

Pass metadata into its `GenericItemDetailPanel`:

```swift
metadataVisible: $isMetadataVisible,
metadata: {
    ContactMetadataInspectorView(contact: contact, onOpenLinkedRef: floatLinkedRef)
}
```

Remove `editorContext`, `.sheet(item:)`, and the old `ContactEditorSheet` usage from `FloatingContactDetail`.

- [ ] **Step 5: Build and run targeted tests**

Run:

```bash
swift test --filter ContactProfileModelsTests
swift test --filter ContactCustomFieldsTests
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cider/Views/CiderPanelView.swift Sources/Cider/Views/CiderPanelView+DetailViews.swift Sources/Cider/Views/CiderPanelView+DetailManagement.swift Sources/Cider/Views/Floating/CiderFloatingItemViews.swift
git commit -m "Wire contact metadata rail across surfaces"
```

---

### Task 6: Add Metadata Rails For Notes, Todos, Date Cards, And Vault Files

**Files:**
- Modify: `Sources/Cider/Views/Notes/InlineNoteEditorView.swift`
- Create: `Sources/Cider/Views/Shared/GenericItemMetadataInspectorViews.swift`
- Modify: `Sources/Cider/Views/CiderPanelView+DetailViews.swift`
- Modify: `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`

- [ ] **Step 1: Create generic metadata inspectors for non-contact items**

Create `Sources/Cider/Views/Shared/GenericItemMetadataInspectorViews.swift`:

```swift
import SwiftUI

struct BasicItemMetadataInspectorView: View {
    let title: String
    let typeLabel: String
    let createdAt: Date
    let updatedAt: Date
    var folderName: String?
    var labelIDs: [UUID] = []
    var linkedRef: LibraryEntityRef
    var extraRows: [ItemMetadataRow] = []
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @State private var isLinkedExpanded = true
    @State private var isFolderExpanded = true
    @State private var isLabelsExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isInfoExpanded = true

    var body: some View {
        ItemMetadataInspectorView {
            Text(title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .padding(.bottom, Spacing.md)

            Divider().background(CiderColors.separator)
            ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
                let rows = relatedRows
                if rows.isEmpty {
                    Text("No linked items.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.quaternary)
                } else {
                    ItemMetadataRowsView(rows: rows, onOpenRef: onOpenLinkedRef)
                }
            }

            if let folderName, !folderName.isEmpty {
                Divider().background(CiderColors.separator)
                ItemMetadataSectionView(title: "Folder", isExpanded: $isFolderExpanded) {
                    ItemMetadataRowsView(rows: [
                        ItemMetadataRow(id: "folder", symbol: "folder", title: folderName)
                    ])
                }
            }

            let labels = labelStorage.labels.filter { labelIDs.contains($0.id) }
            if !labels.isEmpty {
                Divider().background(CiderColors.separator)
                ItemMetadataSectionView(title: "Labels", isExpanded: $isLabelsExpanded) {
                    ItemMetadataRowsView(rows: labels.map {
                        ItemMetadataRow(id: "label-\($0.id.uuidString)", symbol: "tag", title: $0.name)
                    })
                }
            }

            if !extraRows.isEmpty {
                Divider().background(CiderColors.separator)
                ItemMetadataSectionView(title: "Details", isExpanded: $isDetailsExpanded) {
                    ItemMetadataRowsView(rows: extraRows)
                }
            }

            Divider().background(CiderColors.separator)
            ItemMetadataSectionView(title: "Info", isExpanded: $isInfoExpanded) {
                ItemMetadataRowsView(rows: ItemMetadataInfoRows.rows(
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    typeLabel: typeLabel
                ))
            }
        }
    }

    private var relatedRows: [ItemMetadataRow] {
        let refs = (try? ItemLinkService.shared.relatedRefs(for: linkedRef)) ?? []
        return ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
    }
}
```

- [ ] **Step 2: Add helper constructors for each item type**

In the same file, add extensions:

```swift
extension BasicItemMetadataInspectorView {
    init(dateCard: DateCard, onOpenLinkedRef: ((LibraryEntityRef) -> Void)?) {
        self.init(
            title: dateCard.title,
            typeLabel: "Date Card",
            createdAt: dateCard.createdAt,
            updatedAt: dateCard.updatedAt,
            labelIDs: dateCard.labelIDs,
            linkedRef: LibraryEntityRef(type: .dateCard, entityID: dateCard.id),
            extraRows: DateCardMetadataRows.rows(for: dateCard),
            onOpenLinkedRef: onOpenLinkedRef
        )
    }

    init(todo: TodoCard, onOpenLinkedRef: ((LibraryEntityRef) -> Void)?) {
        self.init(
            title: todo.title,
            typeLabel: "Todo",
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt,
            labelIDs: todo.labelIDs,
            linkedRef: LibraryEntityRef(type: .todo, entityID: todo.id),
            extraRows: TodoMetadataRows.rows(for: todo),
            onOpenLinkedRef: onOpenLinkedRef
        )
    }

    init(file: VaultFile, onOpenLinkedRef: ((LibraryEntityRef) -> Void)?) {
        self.init(
            title: file.filename,
            typeLabel: "File",
            createdAt: file.createdAt,
            updatedAt: file.modifiedAt,
            folderName: file.relativePath,
            linkedRef: LibraryEntityRef(type: .vaultFile, entityID: file.id),
            extraRows: [
                ItemMetadataRow(id: "file-type", symbol: file.fileType.systemImageName, title: "Kind", value: file.fileType.displayName),
                ItemMetadataRow(id: "size", symbol: "doc", title: "Size", value: ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
            ],
            onOpenLinkedRef: onOpenLinkedRef
        )
    }
}
```

Add row helpers:

```swift
enum DateCardMetadataRows {
    static func rows(for card: DateCard) -> [ItemMetadataRow] {
        var rows: [ItemMetadataRow] = [
            ItemMetadataRow(id: "date", symbol: "calendar", title: "Date", value: card.startAt.formatted(.dateTime.month(.abbreviated).day().year())),
            ItemMetadataRow(id: "time", symbol: "clock", title: "Time", value: card.allDay ? "All day" : card.startAt.formatted(.dateTime.hour().minute()))
        ]
        if !card.location.isEmpty {
            rows.append(ItemMetadataRow(id: "location", symbol: "mappin.and.ellipse", title: "Location", value: card.location))
        }
        if let amount = card.amount {
            rows.append(ItemMetadataRow(id: "amount", symbol: "dollarsign.circle", title: "Amount", value: String(format: "%.2f", amount)))
        }
        return rows
    }
}

enum TodoMetadataRows {
    static func rows(for todo: TodoCard) -> [ItemMetadataRow] {
        var rows: [ItemMetadataRow] = [
            ItemMetadataRow(id: "status", symbol: todo.isCompleted ? "checkmark.circle.fill" : "circle", title: "Status", value: todo.isCompleted ? "Completed" : "Open")
        ]
        if let dueDate = todo.dueDate {
            rows.append(ItemMetadataRow(id: "due", symbol: "calendar", title: "Due", value: dueDate.formatted(.dateTime.month(.abbreviated).day().year())))
        }
        if let priority = todo.priority {
            rows.append(ItemMetadataRow(id: "priority", symbol: priority.icon, title: "Priority", value: priority.displayName))
        }
        return rows
    }
}
```

- [ ] **Step 3: Wire date, todo, and file rails in main-window details**

In `Sources/Cider/Views/CiderPanelView+DetailViews.swift`, add `metadataVisible: $genericMetadataVisible` and metadata closures to date-card, todo, and vault-file `GenericItemDetailPanel` calls:

```swift
metadataVisible: $genericMetadataVisible,
metadata: {
    BasicItemMetadataInspectorView(dateCard: dateCard, onOpenLinkedRef: openLinkedRef)
}
```

```swift
metadataVisible: $genericMetadataVisible,
metadata: {
    BasicItemMetadataInspectorView(todo: todoCard, onOpenLinkedRef: openLinkedRef)
}
```

```swift
metadataVisible: $genericMetadataVisible,
metadata: {
    BasicItemMetadataInspectorView(file: vaultFile, onOpenLinkedRef: openLinkedRef)
}
```

- [ ] **Step 4: Wire date, todo, and file rails in floating panels**

In `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`, add local `@State private var isMetadataVisible = true` to `FloatingDateCardDetail` and `FloatingTodoDetail`, then pass metadata closures:

```swift
metadataVisible: $isMetadataVisible,
metadata: {
    BasicItemMetadataInspectorView(dateCard: dateCard, onOpenLinkedRef: floatLinkedRef)
}
```

```swift
metadataVisible: $isMetadataVisible,
metadata: {
    BasicItemMetadataInspectorView(todo: todo, onOpenLinkedRef: floatLinkedRef)
}
```

Add a `floatLinkedRef(_:)` helper to each floating detail view using the same implementation as `FloatingContactDetail`.

- [ ] **Step 5: Add note backlinks to the existing note metadata rail**

In `Sources/Cider/Views/Notes/InlineNoteEditorView.swift`, add an optional opener to the editor and sidebar:

```swift
struct InlineNoteEditorView: View {
    @ObservedObject var viewModel: NotesViewModel
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)? = nil
}
```

Pass it through:

```swift
NoteMetadataSidebar(note: note, viewModel: viewModel, onOpenLinkedRef: onOpenLinkedRef)
```

Update the sidebar declaration:

```swift
struct NoteMetadataSidebar: View {
    let note: Note
    @ObservedObject var viewModel: NotesViewModel
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
}
```

Then add:

```swift
@State private var isLinkedExpanded = true
```

Inside `NoteMetadataSidebar.body`, place the linked section after tags:

```swift
sectionDivider
linkedSection
    .padding(.vertical, Spacing.md)
```

Add:

```swift
private var linkedSection: some View {
    ItemMetadataSectionView(title: "Linked", isExpanded: $isLinkedExpanded) {
        let ref = LibraryEntityRef(type: .note, entityID: note.id)
        let refs = (try? ItemLinkService.shared.relatedRefs(for: ref)) ?? []
        let rows = ItemLinkService.shared.summaries(for: refs).map(ItemMetadataRow.related)
        if rows.isEmpty {
            Text("No linked items.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.quaternary)
        } else {
            ItemMetadataRowsView(rows: rows, onOpenRef: onOpenLinkedRef)
        }
    }
}
```

This keeps Markdown formatting in `NotesCompactToolbar` and does not add a second metadata-notes field.

- [ ] **Step 6: Pass note backlink openers from main and floating surfaces**

In `Sources/Cider/Views/CiderPanelView+DetailViews.swift`, update note detail bodies:

```swift
InlineNoteEditorView(viewModel: notesViewModel, onOpenLinkedRef: openLinkedRef)
```

In `Sources/Cider/Views/Floating/CiderFloatingItemViews.swift`, update `FloatingNoteDetail`:

```swift
InlineNoteEditorView(viewModel: viewModel, onOpenLinkedRef: floatLinkedRef)
```

Add this helper to `FloatingNoteDetail`:

```swift
private func floatLinkedRef(_ ref: LibraryEntityRef) {
    guard let linkedSurface = CiderFloatableSurface(linkedRef: ref) else { return }
    NotificationCenter.default.post(
        name: .floatCiderSurface,
        object: linkedSurface,
        userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: linkedSurface]
    )
}
```

- [ ] **Step 7: Build**

Run:

```bash
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add Sources/Cider/Views/Shared/GenericItemMetadataInspectorViews.swift Sources/Cider/Views/CiderPanelView+DetailViews.swift Sources/Cider/Views/Floating/CiderFloatingItemViews.swift Sources/Cider/Views/Notes/InlineNoteEditorView.swift
git commit -m "Add metadata rails for generic item details"
```

---

### Task 7: Confirm CLI Agent Coverage And Help Text

**Files:**
- Modify: `Sources/Cider/Services/ContactCLIHelpText.swift`
- Modify: `Tests/CiderTests/ContactCLIHelpTextTests.swift`
- Modify: `Tests/CiderTests/ItemLinkCLIHelpTextTests.swift`

- [ ] **Step 1: Add help text assertions**

In `Tests/CiderTests/ContactCLIHelpTextTests.swift`, add assertions that contact field and notes operations are discoverable:

```swift
@Test("contact help exposes field and notes operations for agents")
func contactHelpExposesFieldAndNotesOperations() {
    #expect(ContactCLIHelpText.contact.contains("contact field add"))
    #expect(ContactCLIHelpText.contact.contains("contact update <id>"))
    #expect(ContactCLIHelpText.contact.contains("--notes"))
    #expect(ContactCLIHelpText.field.contains("contact field delete"))
}
```

In `Tests/CiderTests/ItemLinkCLIHelpTextTests.swift`, add:

```swift
@Test("link help exposes related command for metadata rails")
func linkHelpExposesRelatedCommand() {
    #expect(ItemLinkCLIHelpText.help.contains("link related"))
    #expect(ItemLinkCLIHelpText.help.contains("link backlinks"))
}
```

- [ ] **Step 2: Run help tests and confirm failures only if copy is missing**

Run:

```bash
swift test --filter ContactCLIHelpTextTests
swift test --filter ItemLinkCLIHelpTextTests
```

Expected: pass if current help already names the commands; otherwise fail with missing substrings.

- [ ] **Step 3: Update help copy when a test fails**

If the contact help test fails, add these lines to `ContactCLIHelpText.contact`:

```swift
cider-cli contact update <id> [--name <n>] [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>]
cider-cli contact field add <contact> --section <s> --label <l> --value <v> [--kind text|phone|email|url|date|number] [--pinned]
cider-cli contact field delete <contact> <field-id|label>
```

If the link help test fails, add these lines to `ItemLinkCLIHelpText.help`:

```swift
cider-cli link backlinks <type> <ref> [--json]
cider-cli link related <type> <ref> [--json]
```

- [ ] **Step 4: Run help tests again**

Run:

```bash
swift test --filter ContactCLIHelpTextTests
swift test --filter ItemLinkCLIHelpTextTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Cider/Services/ContactCLIHelpText.swift Tests/CiderTests/ContactCLIHelpTextTests.swift Tests/CiderTests/ItemLinkCLIHelpTextTests.swift
git commit -m "Document agent metadata commands"
```

---

### Task 8: End-To-End Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --filter ItemMetadataInspectorModelsTests
swift test --filter ContactProfileModelsTests
swift test --filter ContactCustomFieldsTests
swift test --filter ItemLinkServiceTests
swift test --filter ContactCLIHelpTextTests
swift test --filter ItemLinkCLIHelpTextTests
```

Expected: all pass.

- [ ] **Step 2: Run full app build**

Run:

```bash
xcodebuild -scheme CiderApp -project Cider.xcodeproj -configuration Debug -derivedDataPath .deriveddata build
```

Expected: build succeeds.

- [ ] **Step 3: Restart Cider from the fresh build**

Run:

```bash
pkill -x Cider || true
open .deriveddata/Build/Products/Debug/Cider.app
```

Expected: Cider relaunches with the new inspector code.

- [ ] **Step 4: Manual app verification**

Use Computer Use or the in-app browser context to verify:

- Open Baine contact in the main window.
- Toggle the `i` metadata rail off and on.
- Confirm body tabs are `Overview`, `Birthday`, and `Favorites`.
- Confirm `Notes` and `Related` are absent from the contact body.
- Open the contact rail edit mode.
- Add a custom field, save, and confirm it appears in the contact body.
- Edit contact metadata notes, save, close, reopen, and confirm notes persist in the rail.
- Confirm linked/backlinked rows appear in the contact rail and clicking a row opens the target.
- Float the Baine contact into an `NSPanel` and repeat rail toggle plus edit save.
- Open a bookmark and confirm its metadata rail still works.
- Open a note and confirm Markdown formatting remains in the top toolbar while metadata shows links/info.
- Open a todo and confirm checkbox completion remains in the body while metadata shows links/info.
- Open a date card and confirm event facts remain in the body while metadata shows links/info.

- [ ] **Step 5: CLI verification**

Run:

```bash
.deriveddata/Build/Products/Debug/cider-cli contact field add Baine --section Favorites --label TestField --value TestValue --pinned --json
.deriveddata/Build/Products/Debug/cider-cli contact field list Baine --json
.deriveddata/Build/Products/Debug/cider-cli contact field delete Baine TestField --json
.deriveddata/Build/Products/Debug/cider-cli link related contact Baine --json
```

Expected:

- field add returns JSON for `TestField`
- field list includes `TestField`
- field delete returns JSON for the removed field
- link related returns the merged link/backlink list for Baine

- [ ] **Step 6: Final commit if verification changes were needed**

If verification required source edits, run:

```bash
git add Sources Tests
git commit -m "Polish universal metadata inspector"
```

If verification required no edits, do not create an empty commit.
