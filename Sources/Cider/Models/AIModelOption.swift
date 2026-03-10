import Foundation

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let command: String
    /// Argument to pass the user's message in one-shot mode (e.g. "-p" for `claude -p "msg"`)
    let printFlag: String?

    static let builtIn: [AIModelOption] = [
        AIModelOption(id: "shell", name: "Shell", icon: "terminal", command: "", printFlag: nil),
        AIModelOption(id: "claude", name: "Claude", icon: "bubble.left.and.text.bubble.right", command: "claude", printFlag: "-p"),
        AIModelOption(id: "chatgpt", name: "ChatGPT", icon: "bubble.left.and.text.bubble.right", command: "chatgpt", printFlag: nil),
        AIModelOption(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", command: "codex", printFlag: nil),
    ]
}
