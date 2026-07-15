import AppKit
import Foundation

enum CiderLocalApplication: Equatable, Sendable {
    case preview

    var applicationURL: URL {
        switch self {
        case .preview:
            URL(fileURLWithPath: "/System/Applications/Preview.app", isDirectory: true)
        }
    }
}

enum CiderSystemOpenDestination: Equatable, Sendable {
    case accessibilityPrivacySettings

    var url: URL {
        switch self {
        case .accessibilityPrivacySettings:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

enum CiderOpenDestination: Equatable, Sendable {
    /// Content-derived or user-authored web destinations. Only HTTP(S) is accepted.
    case untrustedWeb(URL)
    /// A caller-owned local file or directory opened with its default application.
    case localFile(URL)
    /// A caller-owned local file revealed in Finder.
    case revealInFinder(URL)
    /// Caller-owned local files opened with one allowlisted local application.
    case localFiles([URL], application: CiderLocalApplication)
    /// One allowlisted operating-system destination. Arbitrary system URLs are not accepted.
    case system(CiderSystemOpenDestination)
}

enum CiderOpenError: Error, Equatable, LocalizedError {
    case unsupportedWebScheme
    case invalidLocalDestination
    case openFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedWebScheme:
            "Cider blocked an unsupported web destination."
        case .invalidLocalDestination:
            "Cider blocked an invalid local destination."
        case .openFailed:
            "The destination could not be opened."
        }
    }
}

@MainActor
protocol CiderWorkspaceOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool
    func revealInFinder(_ urls: [URL])
    func open(_ urls: [URL], withApplicationAt applicationURL: URL)
}

@MainActor
private final class SystemCiderWorkspaceOpener: CiderWorkspaceOpening {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func open(_ url: URL) -> Bool {
        workspace.open(url)
    }

    func revealInFinder(_ urls: [URL]) {
        workspace.activateFileViewerSelecting(urls)
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open(urls, withApplicationAt: applicationURL, configuration: configuration)
    }
}

/// The single typed boundary for side effects that leave Cider for a browser,
/// local application, Finder, or an allowlisted operating-system destination.
@MainActor
struct CiderOpenPolicy {
    static let shared = CiderOpenPolicy(workspace: SystemCiderWorkspaceOpener())

    private let workspace: any CiderWorkspaceOpening

    init(workspace: any CiderWorkspaceOpening) {
        self.workspace = workspace
    }

    func openIfAllowed(_ destination: CiderOpenDestination) {
        _ = try? open(destination)
    }

    @discardableResult
    func open(_ destination: CiderOpenDestination) throws -> Bool {
        switch destination {
        case .untrustedWeb(let url):
            guard Self.isAllowedUntrustedWebURL(url) else {
                throw CiderOpenError.unsupportedWebScheme
            }
            guard workspace.open(url) else { throw CiderOpenError.openFailed }
            return true

        case .localFile(let url):
            try validateLocalURL(url)
            guard workspace.open(url) else { throw CiderOpenError.openFailed }
            return true

        case .revealInFinder(let url):
            try validateLocalURL(url)
            workspace.revealInFinder([url])
            return true

        case .localFiles(let urls, let application):
            guard !urls.isEmpty else { throw CiderOpenError.invalidLocalDestination }
            try urls.forEach(validateLocalURL)
            let applicationURL = application.applicationURL
            try validateLocalURL(applicationURL)
            workspace.open(urls, withApplicationAt: applicationURL)
            return true

        case .system(let systemDestination):
            guard workspace.open(systemDestination.url) else { throw CiderOpenError.openFailed }
            return true
        }
    }

    /// Pure validation shared by source-text presentation and the final side-effect
    /// boundary. A web destination must be an absolute HTTP(S) URL with a real host;
    /// credentials and backslash-based authority tricks are rejected.
    nonisolated static func isAllowedUntrustedWebURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              !url.absoluteString.contains("\\") else {
            return false
        }
        return true
    }

    private func validateLocalURL(_ url: URL) throws {
        guard url.isFileURL, !url.path.isEmpty else {
            throw CiderOpenError.invalidLocalDestination
        }
    }
}
