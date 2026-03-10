import Foundation

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let command: String
    /// Arguments for one-shot mode (e.g. ["-p"] for `claude -p "msg"`, ["--continue", "-p"] to resume)
    let printArgs: [String]

    static let builtIn: [AIModelOption] = [
        AIModelOption(id: "shell", name: "Shell", icon: "terminal", command: "", printArgs: []),
        AIModelOption(id: "claude", name: "Claude", icon: "bubble.left.and.text.bubble.right", command: "claude", printArgs: ["--continue", "-p"]),
        AIModelOption(id: "chatgpt", name: "ChatGPT", icon: "bubble.left.and.text.bubble.right", command: "chatgpt", printArgs: []),
        AIModelOption(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", command: "codex", printArgs: []),
    ]
}
