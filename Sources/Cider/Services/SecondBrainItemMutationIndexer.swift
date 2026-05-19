import Foundation
import os

@MainActor
enum SecondBrainItemMutationIndexer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "SecondBrainItemMutationIndexer"
    )

    static func rebuildAfterMutation(database: CiderDatabase?, ownerType: String, ownerID: UUID) {
        guard let database, database.isOpen else { return }

        do {
            _ = try SecondBrainItemContentIndexingService(database: database).rebuild(
                owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID.uuidString)
            )
        } catch {
            logger.error("Failed to rebuild \(ownerType) content chunks for \(ownerID.uuidString): \(error.localizedDescription)")
        }
    }
}
