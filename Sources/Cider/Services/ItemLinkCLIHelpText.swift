import Foundation

enum ItemLinkCLIHelpText {
    static let link = """
    LINKS
      cider-cli link add <source-type> <source-ref> <target-type> <target-ref> [--json]
      cider-cli link remove <source-type> <source-ref> <target-type> <target-ref> [--json]
      cider-cli link list <type> <ref> [--json]
      cider-cli link backlinks <type> <ref> [--json]
      cider-cli link related <type> <ref> [--json]

    TYPES
      bookmark, note, todo, dateCard, contact, vaultFile

    NOTES
      Refs can be UUID prefixes. Names/titles are accepted when they match exactly one item.
    """
}
