import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppInfo: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var path: String

    init(id: UUID = UUID(), name: String, bundleIdentifier: String, path: String) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

// MARK: - Transferable for Drag and Drop

extension AppInfo: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ciderApp)
    }
}

extension UTType {
    static let ciderApp = UTType(exportedAs: "com.cider.app-info")
}
