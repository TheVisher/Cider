import AppKit
import SwiftUI

struct AIAssistantDomainSidebarView: View {
    let isChatListActive: Bool
    let onOpenAssistant: () -> Void

    @ObservedObject private var viewModel = AIAssistantViewModel.shared
    @ObservedObject private var conversationStorage = AIConversationStorage.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionHeader("Chats", count: chatCount)

                if chatCount == 0 {
                    emptyChatsRow
                } else if viewModel.runtimeSelection == .hermes {
                    ForEach(viewModel.hermesChats, id: \.stableID) { chat in
                        hermesChatRow(chat)
                    }
                } else {
                    ForEach(conversationStorage.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.md)
        }
    }

    private var chatCount: Int {
        viewModel.runtimeSelection == .hermes
            ? viewModel.hermesChats.count
            : conversationStorage.conversations.count
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(CiderFont.microMonospaced)
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var emptyChatsRow: some View {
        Button(action: onOpenAssistant) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: Spacing.xl, height: Spacing.xl)

                Text("New Chat")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open AI Assistant")
    }

    private func conversationRow(_ conversation: AIConversationSummary) -> some View {
        let isActive = isChatListActive && viewModel.currentConversationID == conversation.id

        return Button {
            viewModel.loadConversation(conversation.id)
            onOpenAssistant()
        } label: {
            chatRowContent(
                title: conversation.title,
                subtitle: "\(conversation.messageCount) messages",
                systemImage: "bubble.left",
                isActive: isActive,
                badge: nil
            )
        }
        .buttonStyle(.plain)
        .help("Open \(conversation.title)")
    }

    private func hermesChatRow(_ chat: CiderAgentChatRecord) -> some View {
        let isActive = isChatListActive && viewModel.currentConversationID == chat.conversationID
        let messageCount = conversationStorage
            .conversations
            .first(where: { $0.id == chat.conversationID })?
            .messageCount ?? 0

        return Button {
            viewModel.loadHermesChat(stableID: chat.stableID)
            onOpenAssistant()
        } label: {
            chatRowContent(
                title: chat.title,
                subtitle: "\(messageCount) messages",
                systemImage: chat.defaultInCider ? "brain.head.profile" : "bubble.left",
                isActive: isActive,
                badge: chat.defaultInCider ? "Main" : nil
            )
        }
        .buttonStyle(.plain)
        .help("Open \(chat.title)")
        .contextMenu {
            Button("Copy Telegram Resume Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    CiderAgentChatRegistry.telegramResumeCommand(for: chat),
                    forType: .string
                )
            }
        }
    }

    private func chatRowContent(
        title: String,
        subtitle: String,
        systemImage: String,
        isActive: Bool,
        badge: String?
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(CiderFont.bodyMedium)
                .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: Spacing.xl, height: Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if let badge {
                        Text(badge)
                            .font(CiderFont.micro)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Text(subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isActive ? CiderColors.accentSubtle : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
