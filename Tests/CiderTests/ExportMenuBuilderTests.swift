import XCTest
@testable import Cider

final class ExportMenuBuilderTests: XCTestCase {
    func testBookmarkExportUsesCompactSubmenuWithHintInside() {
        let items = ExportMenuBuilder.bookmarkImageExportMenuItems {}

        guard case .submenu("Export", let children) = items.first else {
            return XCTFail("Expected compact Export submenu")
        }
        XCTAssertEqual(children.menuTitles, [
            "Image\u{2026}",
            "Opt-drag to Finder to export image"
        ])
    }

    func testNoteExportUsesCompactSubmenuWithHintInside() {
        let items = ExportMenuBuilder.noteMarkdownExportMenuItems {}

        guard case .submenu("Export", let children) = items.first else {
            return XCTFail("Expected compact Export submenu")
        }
        XCTAssertEqual(children.menuTitles, [
            "Markdown\u{2026}",
            "Opt-drag to Finder to export Markdown"
        ])
    }
}

private extension Array where Element == CardMenuItem {
    var menuTitles: [String] {
        map { item in
            switch item {
            case .action(let title, _, _):
                title
            case .submenu(let title, _):
                title
            case .separator:
                "-"
            case .destructive(let title, _):
                title
            case .disabled(let title):
                title
            case .hint(let title):
                title
            }
        }
    }
}
