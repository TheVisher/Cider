import Foundation

struct AgentRoomsMarkdownDocument: Equatable, Sendable {
    let source: String
    let blocks: [AgentRoomsMarkdownBlock]
}

struct AgentRoomsMarkdownBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem(depth: Int)
        case orderedListItem(depth: Int, ordinal: Int)
        case code(language: String?, isComplete: Bool)
    }

    let id: String
    let kind: Kind
    let content: AttributedString

    var plainText: String { String(content.characters) }

    var links: [URL] {
        content.runs.compactMap(\.link)
    }
}

enum AgentRoomsSafeLinkPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              let host = components.host,
              !host.isEmpty
        else { return false }
        return true
    }
}

enum AgentRoomsMessagePresentation {
    private struct Line {
        let text: String
        let utf16Offset: Int
    }

    private struct Fence {
        let marker: Character
        let count: Int
        let language: String?
    }

    static func document(source: String) -> AgentRoomsMarkdownDocument {
        let lines = source.components(separatedBy: "\n").reduce(into: (lines: [Line](), offset: 0)) { result, text in
            result.lines.append(Line(text: text, utf16Offset: result.offset))
            result.offset += text.utf16.count + 1
        }.lines
        var blocks: [AgentRoomsMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }

            if let opening = openingFence(in: line.text) {
                let startOffset = line.utf16Offset
                var codeLines: [String] = []
                var complete = false
                index += 1
                while index < lines.count {
                    if isClosingFence(lines[index].text, matching: opening) {
                        complete = true
                        index += 1
                        break
                    }
                    codeLines.append(lines[index].text)
                    index += 1
                }
                blocks.append(.init(
                    id: blockID(offset: startOffset, discriminator: "code"),
                    kind: .code(language: opening.language, isComplete: complete),
                    content: AttributedString(codeLines.joined(separator: "\n"))
                ))
                continue
            }

            if let heading = heading(in: line.text) {
                blocks.append(.init(
                    id: blockID(offset: line.utf16Offset, discriminator: "heading"),
                    kind: .heading(level: heading.level),
                    content: inline(heading.text)
                ))
                index += 1
                continue
            }

            if let item = listItem(in: line.text) {
                blocks.append(.init(
                    id: blockID(offset: line.utf16Offset, discriminator: item.discriminator),
                    kind: item.kind,
                    content: inline(item.text)
                ))
                index += 1
                continue
            }

            let paragraphOffset = line.utf16Offset
            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                if candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                if !paragraphLines.isEmpty,
                   openingFence(in: candidate.text) != nil
                    || heading(in: candidate.text) != nil
                    || listItem(in: candidate.text) != nil {
                    break
                }
                paragraphLines.append(candidate.text)
                index += 1
            }
            blocks.append(.init(
                id: blockID(offset: paragraphOffset, discriminator: "paragraph"),
                kind: .paragraph,
                content: inline(paragraphLines.joined(separator: "\n"))
            ))
        }

        return AgentRoomsMarkdownDocument(source: source, blocks: blocks)
    }

    private static func blockID(offset: Int, discriminator: String) -> String {
        "markdown:\(offset):\(discriminator)"
    }

    private static func openingFence(in line: String) -> Fence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let suffix = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        let language = suffix.isEmpty ? nil : String(suffix.prefix(40))
        return Fence(marker: marker, count: count, language: language)
    }

    private static func isClosingFence(_ line: String, matching fence: Fence) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix(while: { $0 == fence.marker }).count
        return count >= fence.count
            && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), trimmed.dropFirst(level).first == " " else { return nil }
        return (level, String(trimmed.dropFirst(level + 1)))
    }

    private static func listItem(in line: String) -> (kind: AgentRoomsMarkdownBlock.Kind, text: String, discriminator: String)? {
        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" })
        let depth = indentation.reduce(0) { partial, character in partial + (character == "\t" ? 1 : 0) }
            + indentation.filter { $0 == " " }.count / 2
        let trimmed = line.dropFirst(indentation.count)
        if let marker = trimmed.first, marker == "-" || marker == "*" || marker == "+",
           trimmed.dropFirst().first == " " {
            return (.unorderedListItem(depth: depth), String(trimmed.dropFirst(2)), "unordered")
        }

        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty,
              let ordinal = Int(digits),
              trimmed.dropFirst(digits.count).hasPrefix(". ")
        else { return nil }
        return (
            .orderedListItem(depth: depth, ordinal: ordinal),
            String(trimmed.dropFirst(digits.count + 2)),
            "ordered"
        )
    }

    private static func inline(_ source: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        let unsafeRanges: [Range<AttributedString.Index>] = attributed.runs.compactMap { run in
            guard let url = run.link, !AgentRoomsSafeLinkPolicy.isAllowed(url) else { return nil }
            return run.range
        }
        for range in unsafeRanges { attributed[range].link = nil }
        return attributed
    }
}

final class AgentRoomsMessagePresentationStore {
    private struct Entry {
        let source: String
        let document: AgentRoomsMarkdownDocument
    }

    private let maximumEntryCount: Int
    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []
    private(set) var parseCount = 0

    init(maximumEntryCount: Int = 256) {
        self.maximumEntryCount = max(16, maximumEntryCount)
    }

    func document(for message: AgentRoomMessage) -> AgentRoomsMarkdownDocument {
        if let entry = entries[message.id], entry.source == message.body { return entry.document }
        let document = AgentRoomsMessagePresentation.document(source: message.body)
        parseCount += 1
        if entries[message.id] == nil { insertionOrder.append(message.id) }
        entries[message.id] = Entry(source: message.body, document: document)
        while insertionOrder.count > maximumEntryCount {
            entries.removeValue(forKey: insertionOrder.removeFirst())
        }
        return document
    }
}

struct AgentRoomsActivityPresentation: Equatable, Sendable {
    let label: String
    let summary: String
    let accessibilityLabel: String

    static func project(_ activity: AgentRoomsLiveActivity) -> Self {
        let label = switch activity.kind {
        case .reasoning: "Thinking"
        case .toolStarted: "Using a tool"
        case .toolCompleted: "Tool finished"
        }
        let cleaned = calmDetail(activity.detail)
        let summary = looksLikeTransportPayload(cleaned) ? "Runtime activity available" : cleaned
        return .init(label: label, summary: summary, accessibilityLabel: "\(label), \(summary)")
    }

    private static func calmDetail(_ source: String) -> String {
        let ansiPattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        let withoutANSI = source.replacingOccurrences(
            of: ansiPattern,
            with: "",
            options: .regularExpression
        )
        let withoutControls = withoutANSI.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
        }
        let collapsed = String(String.UnicodeScalarView(withoutControls))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Activity update" : String(collapsed.prefix(160))
    }

    private static func looksLikeTransportPayload(_ detail: String) -> Bool {
        if detail.localizedCaseInsensitiveContains("jsonrpc")
            || detail.localizedCaseInsensitiveContains("content-length:") {
            return true
        }
        guard (detail.hasPrefix("{") && detail.hasSuffix("}"))
                || (detail.hasPrefix("[") && detail.hasSuffix("]")),
              let data = detail.data(using: .utf8)
        else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

struct AgentRoomsChatStatusPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case checking, ready, sending, streaming, cancelling, unavailable, failed, cancelled, completed
    }

    let state: State
    let title: String
    let detail: String?
    let allowsReconnect: Bool

    static func project(
        transportState: AgentRoomsLiveTransportState,
        turnState: AgentRoomsLiveTurnState,
        receipt: AgentRoomReceipt?,
        message: String?
    ) -> Self {
        if turnState == .idle || turnState == .failed || turnState == .completed {
            switch transportState {
            case .unchecked, .checking:
                return .init(state: .checking, title: "Checking Hermes…", detail: nil, allowsReconnect: false)
            case .blocked:
                return .init(
                    state: .unavailable,
                    title: "Hermes is unavailable",
                    detail: message ?? "Cider could not reach the Hermes Runs service.",
                    allowsReconnect: true
                )
            case .ready:
                break
            }
        }

        switch turnState {
        case .sending:
            return .init(state: .sending, title: "Sending to Hermes…", detail: nil, allowsReconnect: false)
        case .streaming:
            return .init(state: .streaming, title: "Hermes is responding…", detail: nil, allowsReconnect: false)
        case .cancelling:
            return .init(state: .cancelling, title: "Stopping response…", detail: nil, allowsReconnect: false)
        case .failed:
            if receipt?.status == .cancelled {
                return .init(
                    state: .cancelled,
                    title: receipt?.title ?? "Response cancelled",
                    detail: receipt?.detail ?? message,
                    allowsReconnect: false
                )
            }
            return .init(
                state: .failed,
                title: receipt?.title ?? "Message failed",
                detail: receipt?.detail ?? message,
                allowsReconnect: false
            )
        case .completed:
            return .init(
                state: .completed,
                title: "Response complete",
                detail: receipt?.sourceBackedTransport == true ? "Source-backed turn" : nil,
                allowsReconnect: false
            )
        case .idle:
            break
        }

        return .init(state: .ready, title: "Ready", detail: nil, allowsReconnect: false)
    }
}

extension AgentRoomsLiveChatModel {
    var statusPresentation: AgentRoomsChatStatusPresentation {
        AgentRoomsChatStatusPresentation.project(
            transportState: transportState,
            turnState: turnState,
            receipt: activeRoom?.transcript.receipt,
            message: composerMessage
        )
    }
}
