import AppKit
import Combine
import Foundation

private struct ContactsSnapshot: Codable {
    var contacts: [ContactCard]
}

@MainActor
final class ContactStorage: ObservableObject {
    static let shared = ContactStorage()

    @Published private(set) var contacts: [ContactCard] = []

    private let fileName = "_cider_contacts.json"
    private var fileURL: URL {
        let dir = StoragePaths.directoryURL(for: .contacts)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func createContact(id: UUID = UUID(), displayName: String) -> ContactCard {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Contact" : trimmed
        let contact = ContactCard(id: id, displayName: finalName)
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

    @discardableResult
    func assignContact(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = contacts.firstIndex(where: { $0.id == id }) else { return false }
        contacts[idx].folderID = folderID
        contacts[idx].updatedAt = Date()
        persist()
        return true
    }

    func contact(for id: UUID) -> ContactCard? {
        contacts.first { $0.id == id }
    }

    func removeLabelsFromAll(labelID: UUID) {
        var changed = false
        for i in contacts.indices where contacts[i].labelIDs.contains(labelID) {
            contacts[i].labelIDs.removeAll { $0 == labelID }
            contacts[i].updatedAt = Date()
            changed = true
        }
        if changed { persist() }
    }

    func restoreFromTrash(_ contact: ContactCard) {
        guard !contacts.contains(where: { $0.id == contact.id }) else { return }
        contacts.append(contact)
        sortContacts()
        persist()
    }

    // MARK: - Avatar Storage

    func avatarDirectoryURL() -> URL {
        StoragePaths.directoryURL(for: .contacts).appendingPathComponent(".contact-avatars", isDirectory: true)
    }

    func avatarURL(for id: UUID) -> URL {
        avatarDirectoryURL().appendingPathComponent("\(id.uuidString).jpg")
    }

    @discardableResult
    func saveAvatar(_ image: NSImage, for id: UUID) -> Bool {
        let dir = avatarDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return false }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let maxDim: CGFloat = 400
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return false
        }

        do {
            try jpegData.write(to: avatarURL(for: id), options: .atomic)
        } catch { return false }

        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            contacts[idx].hasAvatar = true
            contacts[idx].updatedAt = Date()
            persist()
        }
        return true
    }

    func deleteAvatar(for id: UUID) {
        try? FileManager.default.removeItem(at: avatarURL(for: id))
        if let idx = contacts.firstIndex(where: { $0.id == id }) {
            contacts[idx].hasAvatar = false
            contacts[idx].updatedAt = Date()
            persist()
        }
    }

    // MARK: - Private

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
