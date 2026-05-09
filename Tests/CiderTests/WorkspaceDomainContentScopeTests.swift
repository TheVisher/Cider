import XCTest
@testable import Cider

final class WorkspaceDomainContentScopeTests: XCTestCase {
    func testLibraryShowsAllActiveEntityTypes() {
        let scope = WorkspaceDomainContentScope.defaultScope(for: .browse)

        XCTAssertEqual(scope, .allItems)
        XCTAssertEqual(scope.entityTypes(for: .browse), LibraryEntityType.activeCases)
    }

    func testDomainsDefaultToTheirFocusedEntityTypes() {
        XCTAssertEqual(
            WorkspaceDomainContentScope.defaultScope(for: .bookmarks).entityTypes(for: .bookmarks),
            [.bookmark]
        )
        XCTAssertEqual(
            WorkspaceDomainContentScope.defaultScope(for: .notes).entityTypes(for: .notes),
            [.note]
        )
        XCTAssertEqual(
            WorkspaceDomainContentScope.defaultScope(for: .tasksEvents).entityTypes(for: .tasksEvents),
            [.todo, .dateCard]
        )
    }

    func testAllItemsScopeKeepsDomainFolderEscapeHatchVisible() {
        XCTAssertEqual(
            WorkspaceDomainContentScope.allItems.entityTypes(for: .notes),
            LibraryEntityType.activeCases
        )
        XCTAssertEqual(
            WorkspaceDomainContentScope.defaultScope(for: .projects),
            .allItems
        )
    }
}
