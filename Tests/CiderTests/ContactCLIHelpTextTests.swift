import Testing
@testable import Cider

@Suite("Contact CLI Help Text Tests")
struct ContactCLIHelpTextTests {
    @Test("Contact help advertises profile and field commands")
    func contactHelpAdvertisesProfileAndFieldCommands() {
        let text = ContactCLIHelpText.contact

        #expect(text.contains("cider-cli contact profile show <id|name> [--json]"))
        #expect(text.contains("cider-cli contact field add <id|name> --section <s> --label <l> --value <v>"))
    }

    @Test("Contact profile help advertises JSON apply options")
    func contactProfileHelpAdvertisesJSONApplyOptions() {
        let text = ContactCLIHelpText.profile

        #expect(text.contains("cider-cli contact profile show <id|name> [--json]"))
        #expect(text.contains("cider-cli contact profile apply <id|name> --profile-file <path> [--create] [--json]"))
    }

    @Test("Contact field help advertises field mutation commands")
    func contactFieldHelpAdvertisesMutationCommands() {
        let text = ContactCLIHelpText.field

        #expect(text.contains("cider-cli contact field list <id|name> [--json]"))
        #expect(text.contains("cider-cli contact field update <id|name> <field-id|label>"))
        #expect(text.contains("cider-cli contact field delete <id|name> <field-id|label>"))
    }

    @Test("contact help exposes field and notes operations for agents")
    func contactHelpExposesFieldAndNotesOperations() {
        #expect(ContactCLIHelpText.contact.contains("contact field add"))
        #expect(ContactCLIHelpText.contact.contains("contact update <id-prefix>"))
        #expect(ContactCLIHelpText.contact.contains("--notes"))
        #expect(ContactCLIHelpText.field.contains("contact field delete"))
    }
}
