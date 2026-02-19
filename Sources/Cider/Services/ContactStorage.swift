import Foundation
import Combine

private struct ContactsSnapshot: Codable {
    var contacts: [ContactCard]
}

@MainActor
final class ContactStorage: ObservableObject {
    static let shared = ContactStorage()

    @Published private(set) var contacts: [ContactCard] = []

    private let fileName = "_cider_contacts.json"
    private var fileURL: URL

    private init() {
        let directoryURL = StoragePaths.ciderDataDirectoryURL()
        fileURL = StoragePaths.jsonFileURL(fileName: fileName, in: directoryURL)
        StoragePaths.ensureDirectory(directoryURL)
        load()
    }

    @discardableResult
    func createContact(displayName: String) -> ContactCard {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Contact" : trimmed
        let contact = ContactCard(displayName: finalName)
        contacts.append(contact)
        sortContacts()
        persist()
        return contact
    }

    @discardableResult
    func updateContact(_ updated: ContactCard) -> Bool {
        guard let idx = contacts.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        contacts[idx] = copy
        sortContacts()
        persist()
        return true
    }

    @discardableResult
    func deleteContact(_ id: UUID) -> Bool {
        let oldCount = contacts.count
        contacts.removeAll { $0.id == id }
        guard contacts.count != oldCount else { return false }
        persist()
        return true
    }

    func contact(for id: UUID) -> ContactCard? {
        contacts.first { $0.id == id }
    }

    private func sortContacts() {
        contacts.sort { lhs, rhs in
            let cmp = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ContactsSnapshot.self, from: data)
            contacts = snapshot.contacts
            sortContacts()
        } catch {
            contacts = []
        }
    }

    private func persist() {
        let snapshot = ContactsSnapshot(contacts: contacts)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence.
        }
    }

}
