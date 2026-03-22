import SwiftUI

/// Main tab view for Claude Code agents — mosaic layout with dynamic card sizing.
///
/// All cards live in one masonry grid. Clicking a card expands it in-place —
/// it grows taller to show the chat view while others stay compact and reflow around it.
struct ClaudeSessionsTabView: View {
    @ObservedObject private var manager = ClaudeSessionManager.shared
    @State private var expandedSessionID: UUID?
    @State private var showCreationSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                if !manager.sessions.isEmpty {
                    Text("\(manager.sessions.count)")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.separatorLight)
                        )
                }

                Spacer()

                Button {
                    showCreationSheet = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionMedium)
                        Text("New Agent")
                            .font(CiderFont.captionMedium)
                    }
                    .foregroundColor(CiderColors.controlAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            Divider()

            // Content
            if manager.sessions.isEmpty {
                EmptyStateView(
                    icon: "terminal",
                    title: "No agents yet",
                    subtitle: "Create an agent to start chatting with Claude Code.",
                    actionLabel: "New Agent",
                    action: { showCreationSheet = true }
                )
            } else {
                ScrollView {
                    MasonryLayout(minimumColumnWidth: SessionsDesign.cardMinWidth, itemSpacing: Spacing.sm) {
                        ForEach(manager.sessions) { session in
                            let isExpanded = expandedSessionID == session.id
                            ClaudeSessionCard(
                                session: session,
                                isExpanded: isExpanded,
                                onToggleExpand: {
                                    withAnimation(reduceMotion ? .none : .snappy) {
                                        expandedSessionID = isExpanded ? nil : session.id
                                    }
                                },
                                onStop: { manager.stopSession(session.id) },
                                onDelete: {
                                    withAnimation(reduceMotion ? .none : .snappy) {
                                        if expandedSessionID == session.id { expandedSessionID = nil }
                                        manager.deleteSession(session.id)
                                    }
                                },
                                onSendMessage: { text in manager.sendMessage(text, to: session.id) }
                            )
                            .masonryColumnSpan(isExpanded ? 2 : 1)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .sheet(isPresented: $showCreationSheet) {
            ClaudeSessionCreationSheet(
                onCreate: { name, path in
                    manager.createSession(name: name, projectPath: path)
                    showCreationSheet = false
                },
                onCancel: { showCreationSheet = false }
            )
        }
    }
}
