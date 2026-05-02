import Testing
@testable import Cider

@Suite("Item Link CLI Help Text Tests")
struct ItemLinkCLIHelpTextTests {
    @Test("Link help advertises agent link commands")
    func linkHelpAdvertisesAgentLinkCommands() {
        let text = ItemLinkCLIHelpText.link

        #expect(text.contains("cider-cli link add <source-type> <source-ref> <target-type> <target-ref> [--json]"))
        #expect(text.contains("cider-cli link backlinks <type> <ref> [--json]"))
        #expect(text.contains("bookmark, note, todo, dateCard, contact, vaultFile"))
    }

    @Test("link help exposes related command for metadata rails")
    func linkHelpExposesRelatedCommand() {
        #expect(ItemLinkCLIHelpText.link.contains("link related"))
        #expect(ItemLinkCLIHelpText.link.contains("link backlinks"))
    }
}
