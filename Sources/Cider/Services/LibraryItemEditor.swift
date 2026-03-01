import Foundation

// MARK: - Editor Contexts

/// Triggers `.sheet(item:)` presentation of DateCardEditorSheet.
struct DateCardEditorContext: Identifiable {
    let id = UUID()
    let existingCard: DateCard?
    let defaultDate: Date
}

/// Triggers `.sheet(item:)` presentation of ContactEditorSheet.
struct ContactEditorContext: Identifiable {
    let id = UUID()
    let existingContact: ContactCard?
}

// MARK: - LibraryItemEditor

/// Shared save/create helpers for date cards and contacts.
/// Used by CiderPanelView, SavedViewTabContent, and any other surface
/// that needs to create or edit these entity types.
enum LibraryItemEditor {

    // MARK: - Date Card

    @MainActor
    static func saveDateCard(
        existingCard: DateCard?,
        title: String,
        details: String,
        startAt: Date,
        endAt: Date?,
        allDay: Bool,
        location: String,
        amount: Double?,
        labelIDs: [UUID],
        recurrenceRule: DateCardRecurrenceRule? = nil,
        rules: [SurfacingRule] = []
    ) {
        if var existingCard {
            existingCard.title = title
            existingCard.details = details
            existingCard.startAt = startAt
            existingCard.endAt = endAt
            existingCard.allDay = allDay
            existingCard.location = location
            existingCard.amount = amount
            existingCard.labelIDs = labelIDs
            existingCard.recurrenceRule = recurrenceRule
            existingCard.rules = rules
            _ = DateCardStorage.shared.updateDateCard(existingCard)
            return
        }

        var created = DateCardStorage.shared.createDateCard(
            title: title,
            startAt: startAt,
            endAt: endAt,
            allDay: allDay,
            amount: amount
        )
        created.details = details
        created.location = location
        created.amount = amount
        created.labelIDs = labelIDs
        created.recurrenceRule = recurrenceRule
        created.rules = rules
        _ = DateCardStorage.shared.updateDateCard(created)
    }

    // MARK: - Contact

    @MainActor
    static func saveContact(
        draftContactID: UUID,
        existingContact: ContactCard?,
        displayName: String,
        relationshipLabel: String,
        birthday: Date?,
        notes: String,
        labelIDs: [UUID],
        addBirthdayDateCard: Bool,
        email: String,
        phone: String,
        address: String,
        hasAvatar: Bool
    ) {
        if var existingContact {
            existingContact.displayName = displayName
            existingContact.relationshipLabel = relationshipLabel
            existingContact.birthday = birthday
            existingContact.notes = notes
            existingContact.email = email
            existingContact.phone = phone
            existingContact.address = address
            existingContact.hasAvatar = hasAvatar
            existingContact.labelIDs = labelIDs
            _ = ContactStorage.shared.updateContact(existingContact)
            if addBirthdayDateCard, let birthday {
                createOrUpdateBirthdayDateCard(for: existingContact, birthday: birthday)
            }
            return
        }

        var created = ContactStorage.shared.createContact(id: draftContactID, displayName: displayName)
        created.relationshipLabel = relationshipLabel
        created.birthday = birthday
        created.notes = notes
        created.email = email
        created.phone = phone
        created.address = address
        created.hasAvatar = hasAvatar
        created.labelIDs = labelIDs
        _ = ContactStorage.shared.updateContact(created)

        if addBirthdayDateCard, let birthday {
            createOrUpdateBirthdayDateCard(for: created, birthday: birthday)
        }
    }

    // MARK: - Birthday Date Card

    @MainActor
    static func createOrUpdateBirthdayDateCard(for contact: ContactCard, birthday: Date) {
        var refreshedContact = ContactStorage.shared.contact(for: contact.id) ?? contact
        let targetStart = nextBirthdayOccurrence(from: birthday)

        if let linkedDateCardID = refreshedContact.linkedEntities.first(where: { $0.type == .dateCard })?.entityID,
           var existingBirthdayCard = DateCardStorage.shared.dateCard(for: linkedDateCardID) {
            existingBirthdayCard.title = "\(refreshedContact.displayName) Birthday"
            existingBirthdayCard.details = "Birthday reminder linked to \(refreshedContact.displayName)."
            existingBirthdayCard.startAt = targetStart
            existingBirthdayCard.endAt = nil
            existingBirthdayCard.allDay = true
            existingBirthdayCard.location = ""
            existingBirthdayCard.recurrenceRule = DateCardRecurrenceRule(frequency: .yearly, interval: 1)
            if !existingBirthdayCard.linkedEntities.contains(where: { $0.type == .contact && $0.entityID == refreshedContact.id }) {
                existingBirthdayCard.linkedEntities.append(LibraryEntityRef(type: .contact, entityID: refreshedContact.id))
            }
            _ = DateCardStorage.shared.updateDateCard(existingBirthdayCard)
            if !refreshedContact.linkedEntities.contains(where: { $0.type == .dateCard && $0.entityID == existingBirthdayCard.id }) {
                refreshedContact.linkedEntities.append(LibraryEntityRef(type: .dateCard, entityID: existingBirthdayCard.id))
                _ = ContactStorage.shared.updateContact(refreshedContact)
            }
            return
        }

        var createdBirthdayCard = DateCardStorage.shared.createDateCard(
            title: "\(refreshedContact.displayName) Birthday",
            startAt: targetStart,
            endAt: nil,
            allDay: true
        )
        createdBirthdayCard.details = "Birthday reminder linked to \(refreshedContact.displayName)."
        createdBirthdayCard.recurrenceRule = DateCardRecurrenceRule(frequency: .yearly, interval: 1)
        createdBirthdayCard.linkedEntities.append(LibraryEntityRef(type: .contact, entityID: refreshedContact.id))
        _ = DateCardStorage.shared.updateDateCard(createdBirthdayCard)

        if !refreshedContact.linkedEntities.contains(where: { $0.type == .dateCard && $0.entityID == createdBirthdayCard.id }) {
            refreshedContact.linkedEntities.append(LibraryEntityRef(type: .dateCard, entityID: createdBirthdayCard.id))
            _ = ContactStorage.shared.updateContact(refreshedContact)
        }
    }

    // MARK: - Helpers

    static func nextBirthdayOccurrence(from birthday: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let monthDay = calendar.dateComponents([.month, .day], from: birthday)
        let year = calendar.component(.year, from: now)

        guard
            let month = monthDay.month,
            let day = monthDay.day,
            let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else {
            return birthday
        }

        if candidate >= calendar.startOfDay(for: now) {
            return candidate
        }

        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day)) ?? candidate
    }
}
