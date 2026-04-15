import Foundation
import os

struct AgentThreadHandoff: Codable, Sendable {
    struct RecentTurn: Codable, Sendable {
        let role: AgentMessage.AgentMessageRole
        let content: String
        let timestamp: Date
    }

    let externalKey: String
    let channel: AgentChannel
    let createdAt: Date
    var updatedAt: Date
    var summary: String
    var recentTurns: [RecentTurn]
    var lastRestoredAt: Date?
    var turnCount: Int
}

final class AgentThreadHandoffStorage {
    private let logger = Logger(subsystem: "com.cider.app", category: "AgentThreadHandoffStorage")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let maxRecentTurns = 12
    private let maxRecentCharacters = 6000
    private let retentionWindow: TimeInterval = 7 * 24 * 60 * 60

    private var directoryURL: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("agent-handoffs", isDirectory: true)
    }

    init() {
        ensureDirectory()
        purgeExpiredFiles()
    }

    func load(externalKey: String) -> AgentThreadHandoff? {
        ensureDirectory()
        let url = fileURL(for: externalKey)
        guard let data = try? Data(contentsOf: url),
              var handoff = try? decoder.decode(AgentThreadHandoff.self, from: data)
        else {
            return nil
        }

        if handoff.updatedAt < Date().addingTimeInterval(-retentionWindow) {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        handoff.recentTurns = Array(handoff.recentTurns.suffix(maxRecentTurns))
        return handoff
    }

    func save(thread: AgentThread) {
        ensureDirectory()

        let recentTurns = trimmedRecentTurns(from: thread.messages)
        let summary = summarize(thread: thread, recentTurns: recentTurns)
        let handoff = AgentThreadHandoff(
            externalKey: thread.externalKey,
            channel: thread.channel,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            summary: summary,
            recentTurns: recentTurns,
            lastRestoredAt: thread.restoredFromHandoffAt,
            turnCount: thread.messages.filter { $0.role != .toolResult }.count
        )

        do {
            let data = try encoder.encode(handoff)
            try data.write(to: fileURL(for: thread.externalKey), options: .atomic)
        } catch {
            logger.error("Failed to save handoff for \(thread.externalKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func markRestored(_ handoff: AgentThreadHandoff) {
        var updated = handoff
        updated.lastRestoredAt = Date()
        do {
            let data = try encoder.encode(updated)
            try data.write(to: fileURL(for: handoff.externalKey), options: .atomic)
        } catch {
            logger.error("Failed to mark handoff restored for \(handoff.externalKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func trimmedRecentTurns(from messages: [AgentMessage]) -> [AgentThreadHandoff.RecentTurn] {
        let nonTool = messages
            .filter { $0.role != .toolResult }
            .map { message in
                AgentThreadHandoff.RecentTurn(
                    role: message.role,
                    content: trimmedLine(message.content),
                    timestamp: message.timestamp
                )
            }

        var selected: [AgentThreadHandoff.RecentTurn] = []
        var totalCharacters = 0
        for turn in nonTool.reversed() {
            let nextSize = totalCharacters + turn.content.count
            if selected.count >= maxRecentTurns || (!selected.isEmpty && nextSize > maxRecentCharacters) {
                break
            }
            selected.append(turn)
            totalCharacters = nextSize
        }
        return selected.reversed()
    }

    private func summarize(thread: AgentThread, recentTurns: [AgentThreadHandoff.RecentTurn]) -> String {
        let userTurns = recentTurns.filter { $0.role == .user }
        let assistantTurns = recentTurns.filter { $0.role == .assistant }

        var lines: [String] = []
        if let latestUser = userTurns.last?.content, !latestUser.isEmpty {
            lines.append("Latest user ask: \(latestUser)")
        }

        if userTurns.count > 1 {
            let earlier = userTurns
                .dropLast()
                .suffix(2)
                .map(\.content)
                .joined(separator: " | ")
            if !earlier.isEmpty {
                lines.append("Recent user context: \(earlier)")
            }
        }

        if let latestAssistant = assistantTurns.last?.content, !latestAssistant.isEmpty {
            lines.append("Latest assistant reply: \(latestAssistant)")
        }

        if let restoredAt = thread.restoredFromHandoffAt {
            let formatter = ISO8601DateFormatter()
            lines.append("This thread was restored from a saved handoff at \(formatter.string(from: restoredAt)).")
        }

        return lines.joined(separator: "\n")
    }

    private func fileURL(for externalKey: String) -> URL {
        let safeKey = externalKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directoryURL.appendingPathComponent("\(safeKey).json")
    }

    private func ensureDirectory() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create handoff directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func purgeExpiredFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-retentionWindow)
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let handoff = try? decoder.decode(AgentThreadHandoff.self, from: data)
            else {
                continue
            }
            if handoff.updatedAt < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func trimmedLine(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if flattened.count <= 320 {
            return flattened
        }
        let cutoff = flattened.index(flattened.startIndex, offsetBy: 317)
        return String(flattened[..<cutoff]) + "..."
    }
}
