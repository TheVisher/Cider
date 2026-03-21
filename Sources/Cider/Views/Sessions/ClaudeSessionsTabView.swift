import SwiftUI

/// Main tab view for Claude Code sessions — masonry card layout with create button.
struct ClaudeSessionsTabView: View {
    @ObservedObject private var manager = ClaudeSessionManager.shared
    @State private var expandedSessionID: UUID?
    @State private var showCreationSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer()

                Button {
                    showCreationSheet = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionMedium)
                        Text("New Session")
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
                    title: "No sessions yet",
                    subtitle: "Create a session to start chatting with Claude Code agents.",
                    actionLabel: "New Session",
                    action: { showCreationSheet = true }
                )
            } else {
                ScrollView {
                    MasonryLayout(minimumColumnWidth: SessionsDesign.cardMinWidth, itemSpacing: Spacing.sm) {
                        ForEach(manager.sessions) { session in
                            ClaudeSessionCard(
                                session: session,
                                isExpanded: expandedSessionID == session.id,
                                onToggleExpand: {
                                    withAnimation(reduceMotion ? .none : .snappy) {
                                        expandedSessionID = expandedSessionID == session.id ? nil : session.id
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
