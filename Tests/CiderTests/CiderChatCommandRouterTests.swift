import Testing
@testable import Cider

struct CiderChatCommandRouterTests {
    @Test("normal chat messages are not slash commands")
    func normalMessagesAreNotSlashCommands() throws {
        #expect(try CiderChatCommandRouter.parse("save this restaurant") == nil)
    }

    @Test("help command returns local help")
    func helpCommandReturnsLocalHelp() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/help"))

        #expect(command.name == "help")
        guard case .localMessage(let message) = command.action else {
            Issue.record("Expected local help message")
            return
        }
        #expect(message.contains("/status"))
        #expect(message.contains("/resume"))
    }

    @Test("status command requests native status")
    func statusCommandRequestsNativeStatus() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/status"))

        #expect(command.name == "status")
        #expect(command.action == .showStatus)
    }

    @Test("resume command defaults to Cider")
    func resumeCommandDefaultsToCider() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/resume"))

        #expect(command.name == "resume")
        #expect(command.argument == nil)
        #expect(command.action == .resume(title: "Cider"))
    }

    @Test("resume command preserves explicit title")
    func resumeCommandPreservesExplicitTitle() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/resume Cider Scratchpad"))

        #expect(command.name == "resume")
        #expect(command.argument == "Cider Scratchpad")
        #expect(command.action == .resume(title: "Cider Scratchpad"))
    }

    @Test("last command requests cached assistant response")
    func lastCommandRequestsCachedAssistantResponse() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/last"))

        #expect(command.name == "last")
        #expect(command.action == .showLastResponse)
    }

    @Test("summary command becomes Hermes prompt")
    func summaryCommandBecomesHermesPrompt() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/summary"))

        #expect(command.name == "summary")
        guard case .sendToHermes(let prompt) = command.action else {
            Issue.record("Expected Hermes summary prompt")
            return
        }
        #expect(prompt.contains("summarize"))
        #expect(prompt.contains("Cider chat"))
    }

    @Test("checkpoint command becomes Hermes prompt")
    func checkpointCommandBecomesHermesPrompt() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/checkpoint"))

        #expect(command.name == "checkpoint")
        guard case .sendToHermes(let prompt) = command.action else {
            Issue.record("Expected Hermes checkpoint prompt")
            return
        }
        #expect(prompt.contains("checkpoint"))
        #expect(prompt.contains("durable"))
    }

    @Test("new command asks for confirmation before starting fresh")
    func newCommandAsksForConfirmationBeforeStartingFresh() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/new"))

        #expect(command.name == "new")
        guard case .localMessage(let message) = command.action else {
            Issue.record("Expected local confirmation message")
            return
        }
        #expect(message.contains("/new confirm"))
    }

    @Test("new confirm command starts fresh chat")
    func newConfirmCommandStartsFreshChat() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/new confirm"))

        #expect(command.name == "new")
        #expect(command.argument == "confirm")
        #expect(command.action == .startFreshChat)
    }

    @Test("title command returns rename action")
    func titleCommandReturnsRenameAction() throws {
        let command = try #require(try CiderChatCommandRouter.parse("/title Cider Scratchpad"))

        #expect(command.name == "title")
        #expect(command.argument == "Cider Scratchpad")
        #expect(command.action == .renameCurrentChat("Cider Scratchpad"))
    }

    @Test("unknown slash command throws local parse error")
    func unknownSlashCommandThrowsLocalParseError() throws {
        #expect(throws: CiderChatCommandRouter.Error.unsupportedCommand("wat")) {
            try CiderChatCommandRouter.parse("/wat")
        }
    }
}
