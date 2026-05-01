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
            address: "Home",
            customFields: [
                ContactCustomField(
                    section: "Favorites",
                    label: "Color",
                    value: "Black",
                    kind: .text,
                    isPinned: true
                )
            ]
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
        #expect(rows.map(\.kind).contains(.customField))
        #expect(rows.map(\.text).contains("Color: Black"))
    }

    @Test("custom fields are grouped by section")
    func customFieldsAreGroupedBySection() {
        let contact = ContactCard(
            displayName: "Baine",
            customFields: [
                ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text),
                ContactCustomField(section: "School", label: "Teacher", value: "Ms. Example", kind: .text)
            ]
        )

        let groups = ContactProfileCustomFields.groupedRows(for: contact)

        #expect(groups.map { $0.section } == ["Favorites", "School"])
        #expect(groups[0].rows.map(\.displayText) == ["Color: Black"])
        #expect(groups[1].rows.map(\.displayText) == ["Teacher: Ms. Example"])
    }

    @Test("note preview preserves readable markdown block boundaries")
    func notePreviewPreservesReadableMarkdownBlockBoundaries() {
        let lines = ContactProfileNotePreview.lines(
            from: """
            # Baine

            ## Basics
            - Relationship: Son
            - Birthday: June 15, 2016

            ## Favorites
            - Color: Black
            """,
            contact: ContactCard(displayName: "Baine")
        )

        #expect(lines == [
            "Basics",
            "Relationship: Son",
            "Birthday: June 15, 2016",
            "Favorites",
            "Color: Black"
        ])
    }

    @Test("overview note preview hides facts already represented by fields")
    func overviewNotePreviewHidesRepresentedFacts() {
        let birthday = Calendar.current.date(from: DateComponents(year: 2016, month: 6, day: 15))!
        let contact = ContactCard(
            displayName: "Baine",
            relationshipLabel: "Son",
            birthday: birthday,
            customFields: [
                ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text)
            ]
        )

        let lines = ContactProfileNotePreview.lines(
            from: """
            # Baine

            ## Basics
            - Relationship: Son
            - Birthday: June 15, 2016

            ## Favorites
            - Color: Black
            """,
            contact: contact
        )

        #expect(lines.isEmpty)
    }

    @Test("favorites prefer structured fields and ignore markdown headings")
    func favoritesPreferStructuredFieldsAndIgnoreMarkdownHeadings() {
        let contact = ContactCard(
            displayName: "Baine",
            notes: """
            # Baine

            ## Favorites
            - Color: Black
            """,
            customFields: [
                ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text)
            ]
        )

        #expect(ContactProfileFavorites.lines(for: contact) == ["Color: Black"])
    }

    @Test("card preview uses structured fields and cleaned note lines")
    func cardPreviewUsesStructuredFieldsAndCleanedNoteLines() {
        let contact = ContactCard(
            displayName: "Baine",
            notes: """
            # Baine

            ## Basics
            - Relationship: Son

            ## Favorites
            - Color: Black
            """,
            customFields: [
                ContactCustomField(section: "Favorites", label: "Color", value: "Black", kind: .text)
            ]
        )

        #expect(ContactProfileCardPreview.lines(for: contact, limit: 3) == [
            "Color: Black",
            "Basics",
            "Relationship: Son"
        ])
    }

    @Test("contact profile tabs only include person profile sections")
    func contactProfileTabsOnlyIncludePersonProfileSections() {
        #expect(ContactProfileTab.allCases == [.overview, .birthday, .favorites])
    }

    @Test("essentials can show for every remaining contact profile tab")
    func essentialsCanShowForEveryRemainingContactTab() {
        #expect(ContactProfileEssentials.shouldShowRail(for: .overview))
        #expect(ContactProfileEssentials.shouldShowRail(for: .birthday))
        #expect(ContactProfileEssentials.shouldShowRail(for: .favorites))
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

    @Test("related missing labels are human readable")
    func relatedMissingLabelsAreHumanReadable() {
        let bookmark = ContactProfileRelatedItem(
            ref: LibraryEntityRef(type: .bookmark, entityID: UUID()),
            title: nil,
            subtitle: nil
        )
        let date = ContactProfileRelatedItem(
            ref: LibraryEntityRef(type: .dateCard, entityID: UUID()),
            title: nil,
            subtitle: nil
        )

        #expect(bookmark.title == "Missing bookmark")
        #expect(date.title == "Missing date card")
    }

    @Test("related refs merge outgoing and backlinks without duplicates")
    func relatedRefsMergeOutgoingAndBacklinksWithoutDuplicates() {
        let contactRef = LibraryEntityRef(type: .contact, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())

        let refs = ContactProfileRelatedRefs.merged(
            outgoing: [bookmark, contactRef],
            backlinks: [bookmark, note],
            excluding: contactRef
        )

        #expect(refs == [bookmark, note])
    }
}
