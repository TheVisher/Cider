import AppKit
import os.log

/// Sends iMessages via AppleScript through Messages.app.
@MainActor
enum iMessageSender {
    private static let logger = Logger(subsystem: "com.cider.app", category: "iMessageSender")

    /// Send a message to a specific chat by its chat ID.
    static func send(_ text: String, toChatID chatID: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Messages"
            set targetChat to chat id "\(chatID)"
            send "\(escaped)" to targetChat
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                logger.error("AppleScript send-to-chat error: \(error)")
            }
        }
    }

    /// Send a message to a participant by phone number or email address.
    static func send(_ text: String, toParticipant participant: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(participant)" of targetService
            send "\(escaped)" to targetBuddy
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                logger.error("AppleScript send-to-participant error: \(error)")
            }
        }
    }
}
