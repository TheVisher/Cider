import Testing
@testable import Cider

struct MetadataRailExpansionPolicyTests {
    @Test("editable empty sections start collapsed")
    func editableEmptySectionsStartCollapsed() {
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .folder, hasContent: false))
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .tags, hasContent: false))
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .notes, hasContent: false))
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .sources, hasContent: false))
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .history, hasContent: false))
        #expect(!MetadataRailExpansionPolicy.defaultExpanded(for: .intelligence, hasContent: false))
    }

    @Test("sections with content start expanded")
    func sectionsWithContentStartExpanded() {
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .folder, hasContent: true))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .tags, hasContent: true))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .notes, hasContent: true))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .sources, hasContent: true))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .history, hasContent: true))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .intelligence, hasContent: true))
    }

    @Test("primary and info sections stay expanded by default")
    func primaryAndInfoSectionsStayExpanded() {
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .title, hasContent: false))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .source, hasContent: false))
        #expect(MetadataRailExpansionPolicy.defaultExpanded(for: .info, hasContent: false))
    }
}
