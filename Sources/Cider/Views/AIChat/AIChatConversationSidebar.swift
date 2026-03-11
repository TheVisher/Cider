import SwiftUI

struct AIChatConversationSidebar: View {
    @ObservedObject var viewModel: AIChatViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                Spacer()

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        viewModel.newConversation()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(
                            width: CiderPanelDesign.trafficLightTapTarget,
                            height: CiderPanelDesign.trafficLightTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.sm)

            // Conversation list
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(viewModel.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .frame(width: 220)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                CiderColors.acrylicTint
                CiderColors.surfaceHighlight
            }
        )
    }

    // MARK: - Conversation Row

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        let isSelected = conversation.id == viewModel.currentConversationID
        let isRenaming = renamingID == conversation.id

        return Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                viewModel.selectConversation(conversation)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if isRenaming {
                    TextField("Title", text: $renameText, onCommit: {
                        viewModel.renameConversation(id: conversation.id, to: renameText)
                        renamingID = nil
                    })
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                } else {
                    Text(conversation.title)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                }

                Text(formattedDate(conversation.updatedAt))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)

                if !conversation.preview.isEmpty && !isRenaming {
                    Text(conversation.preview)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.selectedFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? CiderColors.selectedBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameText = conversation.title
                renamingID = conversation.id
            }
            Divider()
            Button("Delete", role: .destructive) {
                withAnimation(reduceMotion ? .none : .snappy) {
                    viewModel.deleteConversation(id: conversation.id)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(CiderColors.tertiary)
            Text("No conversations yet")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
