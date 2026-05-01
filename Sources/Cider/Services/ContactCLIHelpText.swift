import Foundation

enum ContactCLIHelpText {
    static let contact = """
    CONTACTS
      cider-cli contact list [--json]
      cider-cli contact create <name> [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>] [--folder <name|path>]
      cider-cli contact update <id-prefix> [--name <n>] [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>]
      cider-cli contact delete <id-prefix>
      cider-cli contact profile show <id|name> [--json]
      cider-cli contact profile apply <id|name> --profile-json <json> [--create] [--json]
      cider-cli contact profile apply <id|name> --profile-file <path> [--create] [--json]
      cider-cli contact field list <id|name> [--json]
      cider-cli contact field add <id|name> --section <s> --label <l> --value <v> [--kind text|phone|email|url|date|number] [--pinned]
      cider-cli contact field update <id|name> <field-id|label> [--section <s>] [--label <l>] [--value <v>] [--kind text|phone|email|url|date|number] [--pinned true|false]
      cider-cli contact field delete <id|name> <field-id|label>
      cider-cli contact export <id-prefix> --to <path.vcf>
      cider-cli contact set-avatar <id-prefix> <image-path>
      cider-cli contact remove-avatar <id-prefix>
    """

    static let profile = """
    CONTACT PROFILE
      cider-cli contact profile show <id|name> [--json]
      cider-cli contact profile apply <id|name> --profile-json <json> [--create] [--json]
      cider-cli contact profile apply <id|name> --profile-file <path> [--create] [--json]

    NOTES
      --profile-json accepts inline JSON. Use --profile-json - to read JSON from stdin.
      --create creates the contact when no existing id or name matches.
    """

    static let field = """
    CONTACT FIELDS
      cider-cli contact field list <id|name> [--json]
      cider-cli contact field add <id|name> --section <s> --label <l> --value <v> [--kind text|phone|email|url|date|number] [--pinned]
      cider-cli contact field update <id|name> <field-id|label> [--section <s>] [--label <l>] [--value <v>] [--kind text|phone|email|url|date|number] [--pinned true|false]
      cider-cli contact field delete <id|name> <field-id|label>

    FIELD KINDS
      text, phone, email, url, date, number
    """
}
