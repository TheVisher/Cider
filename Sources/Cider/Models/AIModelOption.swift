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
    /// Hint shown when the CLI is not installed (e.g. the npm install command).
    let installHint: String

    /// AI agent models — shown as primary pills.
    static let aiModels: [AIModelOption] = [
        AIModelOption(id: "claude", name: "Claude", icon: "bubble.left.and.text.bubble.right", command: "claude", printArgs: ["--dangerously-skip-permissions", "-p"], continueArgs: ["--continue"], installHint: "npm install -g @anthropic-ai/claude-code"),
        AIModelOption(id: "gemini", name: "Gemini", icon: "bubble.left.and.text.bubble.right", command: "gemini", printArgs: ["-p"], continueArgs: [], installHint: "npm install -g @google/gemini-cli"),
        AIModelOption(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", command: "codex", printArgs: ["exec", "--skip-git-repo-check"], continueArgs: [], installHint: "npm install -g @openai/codex"),
    ]

    /// Shell mode — shown behind a chevron expander.
    static let shell = AIModelOption(id: "shell", name: "Shell", icon: "terminal", command: "", printArgs: [], continueArgs: [], installHint: "")

    /// All options (AI models + shell). Kept for backward compatibility.
    static let builtIn: [AIModelOption] = aiModels + [shell]
}
