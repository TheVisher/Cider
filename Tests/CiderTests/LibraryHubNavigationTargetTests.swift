import Foundation
import Testing
@testable import Cider

struct LibraryHubNavigationTargetTests {
    @Test("safe hub query command parses into read-only search navigation")
    func safeHubQueryCommandParsesIntoSearchNavigation() throws {
        let target = try #require(LibraryHubNavigationTarget(command: "cider-cli item hub --query \"WoW\" --limit 5 --json"))

        #expect(target == .query("WoW"))
        #expect(target.readOnly)
        #expect(!target.promotesTruth)
    }

    @Test("safe positional hub query command parses into read-only search navigation")
    func safePositionalHubQueryCommandParsesIntoSearchNavigation() throws {
        let target = try #require(LibraryHubNavigationTarget(command: "cider-cli item hub \"World of Warcraft\" --json"))

        #expect(target == .query("World of Warcraft"))
        #expect(target.libraryRoute == .search("World of Warcraft"))
    }

    @Test("safe hub item command parses into a concrete library ref")
    func safeHubItemCommandParsesIntoConcreteLibraryRef() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let target = try #require(LibraryHubNavigationTarget(command: "cider-cli item hub bookmark \(id.uuidString) --json"))

        #expect(target == .item(LibraryEntityRef(type: .bookmark, entityID: id)))
        #expect(target.libraryRoute == nil)
    }

    @Test("unknown mutating non-hub and malformed commands are rejected")
    func unsafeCommandsAreRejected() {
        let commands = [
            "cider-cli item route bookmark 11111111-1111-1111-1111-111111111111 --target Inbox --json",
            "cider-cli item hub --accept --json",
            "cider-cli item hub --query \"WoW\" --accept --json",
            "cider-cli item hub --query \"WoW\" --limit five --json",
            "cider-cli item hub externalFile 11111111-1111-1111-1111-111111111111 --json",
            "cider-cli item hub",
            "rm -rf ~/CiderVault",
        ]

        for command in commands {
            #expect(LibraryHubNavigationTarget(command: command) == nil)
        }
    }
}
