import AppKit
import os.log

/// Sends iMessages via AppleScript through Messages.app.
@MainActor
enum iMessageSender {
    private static let logger = Logger(subsystem: "com.cider.app", category: "iMessageSender")

    /// Send a message to a specific chat by its chat ID.
    /// Uses osascript subprocess to avoid NSAppleScript main thread blocking.
    static func send(_ text: String, toChatID chatID: String) {
        logger.info("Sending via osascript to: \(chatID, privacy: .private)")

        // Use osascript as a subprocess so it can't freeze the main thread
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", """
            tell application "Messages"
                try
                    set targetService to 1st account whose service type = iMessage
                    set targetBuddy to participant "\(chatID)" of targetService
                    send (do shell script "cat " & quoted form of "\(writeTempFile(text))") to targetBuddy
                on error errMsg
                    try
                        set targetChat to chat id "\(chatID)"
                        send (do shell script "cat " & quoted form of "\(writeTempFile(text))") to targetChat
                    end try
                end try
            end tell
            """
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Don't wait — let it send in the background
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    Task { @MainActor in
                        logger.info("osascript send succeeded")
                    }
                } else {
                    Task { @MainActor in
                        logger.error("osascript send failed with exit code \(proc.terminationStatus)")
                    }
                }
            }
        } catch {
            logger.error("Failed to launch osascript: \(error.localizedDescription)")
        }
    }

    /// Send a message to a participant by phone number or email address.
    static func send(_ text: String, toParticipant participant: String) {
        send(text, toChatID: participant)
    }

    /// Write text to a temp file and return the path. Used by AppleScript via `do shell script "cat ..."`.
    private static func writeTempFile(_ text: String) -> String {
        let path = NSTemporaryDirectory() + "cider_imsg_\(UUID().uuidString).txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        // Clean up after a delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(atPath: path)
        }
        return path
    }
}
