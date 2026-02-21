import Foundation

struct ExternalSource: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String          // absolute, tilde-expanded filesystem path
    var displayName: String   // user-facing name shown in sidebar and tab bar
    var showInSidebar: Bool   // always true; kept for future per-source control
    var isTabPinned: Bool     // appears as a tab in CiderTabBar
    var showInLibrary: Bool   // files appear in the Home library feed
    var createdAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        displayName: String,
        showInSidebar: Bool = true,
        isTabPinned: Bool = false,
        showInLibrary: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.showInSidebar = showInSidebar
        self.isTabPinned = isTabPinned
        self.showInLibrary = showInLibrary
        self.createdAt = createdAt
    }
}
