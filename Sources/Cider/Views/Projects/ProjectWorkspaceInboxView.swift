import SwiftUI

struct ProjectWorkspaceInboxView: View {
    let workspace: ProjectWorkspace
    let entries: [ProjectWorkspaceInboxEntry]
    var onOpenCard: (String, String) -> Void
    var onMarkReviewed: (String, String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if entries.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "Inbox is clear",
                        subtitle: "Reviewed cards stay in their current board columns. New agent reports and QA-ready work will appear here."
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(entries) { entry in
                            inboxCard(entry)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Inbox", systemImage: entries.isEmpty ? "tray" : "tray.full")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            Text("Unread agent work and review items for \(workspace.title). Marking reviewed removes cards from this Inbox without changing board status.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inboxCard(_ entry: ProjectWorkspaceInboxEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(entry.card.displayKey ?? String(entry.card.id.prefix(8)).uppercased())
                        .font(CiderFont.microMonospaced)
                        .foregroundColor(CiderColors.tertiary)

                    Text(entry.boardName)
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)

                    Text("/ \(entry.columnName)")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                }

                Text(entry.card.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    ForEach(entry.badges) { badge in
                        inboxBadge(badge)
                    }
                }

                if let preview = KanbanBoardLayout.previewText(for: entry.card) {
                    Text(preview)
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary.opacity(0.72))
                        .lineLimit(KanbanDesign.cardPreviewBodyLineLimit)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Button {
                    onOpenCard(entry.boardID, entry.card.id)
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(CiderFont.captionMedium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onMarkReviewed(entry.boardID, entry.card.id)
                } label: {
                    Label("Reviewed", systemImage: "checkmark")
                        .font(CiderFont.captionMedium)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.controlAccent)
                .help("Remove from Inbox without moving the card")
            }
        }
        .padding(Spacing.md)
        .sectionContainer(cornerRadius: Radius.sm)
    }

    private func inboxBadge(_ badge: ProjectWorkspaceInboxBadge) -> some View {
        Label(badge.title, systemImage: badge.systemImage)
            .font(CiderFont.micro)
            .foregroundColor(badgeColor(for: badge.kind))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(badgeColor(for: badge.kind).opacity(0.12))
            )
    }

    private func badgeColor(for kind: ProjectWorkspaceInboxBadge.Kind) -> Color {
        switch kind {
        case .new: return CiderColors.controlAccent
        case .agentReport: return CiderColors.secondary
        case .needsQA: return CiderColors.warning
        }
    }
}
