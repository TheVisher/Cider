import Foundation

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let command: String
    /// Base arguments for one-shot mode (e.g. ["-p"] for `claude -p "msg"`)
    let printArgs: [String]
    /// Arguments to prepend when continuing an existing conversation (e.g. ["--continue"])
    let continueArgs: [String]

    static let builtIn: [AIModelOption] = [
        AIModelOption(id: "shell", name: "Shell", icon: "terminal", command: "", printArgs: [], continueArgs: []),
        AIModelOption(id: "claude", name: "Claude", icon: "bubble.left.and.text.bubble.right", command: "claude", printArgs: ["-p"], continueArgs: ["--continue"]),
        AIModelOption(id: "chatgpt", name: "ChatGPT", icon: "bubble.left.and.text.bubble.right", command: "chatgpt", printArgs: [], continueArgs: []),
        AIModelOption(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", command: "codex", printArgs: [], continueArgs: []),
    ]
}
