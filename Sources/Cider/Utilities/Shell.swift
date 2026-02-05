import Foundation

enum Shell {
    @discardableResult
    static func run(_ command: String) -> String {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
