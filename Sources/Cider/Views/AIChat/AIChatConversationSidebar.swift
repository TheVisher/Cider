import SwiftUI

struct AIChatConversationSidebar: View {
    @ObservedObject var viewModel: AIChatViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)

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
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            // Conversation list
            if viewModel.conversations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xxs) {
                        ForEach(viewModel.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
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
        .overlay(alignment: .trailing) {
            // Right-edge border to separate from chat area
            Rectangle()
                .fill(CiderColors.borderDefault)
                .frame(width: 1)
        }
    }

    // MARK: - Conversation Row

    @ViewBuilder
    private func conversationRow(_ conversation: ChatConversation) -> some View {
        let isSelected = conversation.id == viewModel.currentConversationID
        let isRenaming = renamingID == conversation.id

        if isRenaming {
            // Rename mode — standalone text field, not inside a button
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                TextField("Title", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .focused($isRenameFieldFocused)
                    .onSubmit {
                        commitRename(conversation.id)
                    }

                Text(formattedDate(conversation.updatedAt))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.selectedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(CiderColors.accentBorder, lineWidth: 1)
            )
            .onAppear {
                isRenameFieldFocused = true
            }
            .onExitCommand {
                renamingID = nil
            }
        } else {
            // Normal row — clickable button
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    viewModel.selectConversation(conversation)
                }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(conversation.title)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
                        .lineLimit(1)

                    Text(formattedDate(conversation.updatedAt))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
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
                .contentShape(Rectangle())
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

    private func commitRename(_ id: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            viewModel.renameConversation(id: id, to: trimmed)
        }
        renamingID = nil
    }

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
