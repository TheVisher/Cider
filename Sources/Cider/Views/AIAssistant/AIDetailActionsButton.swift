import SwiftUI

/// AI quick action button for detail panels. Shows a sparkles icon that opens
/// a popover with context-specific AI actions.
struct AIDetailActionsButton: View {
    var bookmarkTitle: String?
    var bookmarkURL: String?
    var noteTitle: String?
    var eventTitle: String?
    var contactName: String?
    var todoTitle: String?
    var folderName: String?

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(CiderFont.label)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("AI Actions")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Actions")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            ForEach(actions, id: \.label) { action in
                Button {
                    showPopover = false
                    action.execute()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: action.icon)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.controlAccent)
                            .frame(width: 14, alignment: .center)
                        Text(action.label)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.primary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 200)
    }

    private var actions: [AIDetailAction] {
        var list: [AIDetailAction] = []

        if let title = bookmarkTitle {
            list.append(AIDetailAction(icon: "text.quote", label: "Summarize") {
                sendMessage("Summarize the bookmark \"\(title)\"")
            })
            list.append(AIDetailAction(icon: "rectangle.stack", label: "Find Similar") {
                sendMessage("Find bookmarks similar to \"\(title)\"")
            })
            list.append(AIDetailAction(icon: "tag", label: "Suggest Tags") {
                sendMessage("What tags would you suggest for the bookmark \"\(title)\"?")
            })
            list.append(AIDetailAction(icon: "folder", label: "Suggest Folder") {
                sendMessage("What folder should the bookmark \"\(title)\" go in?")
            })
        }

        if let title = noteTitle {
            list.append(AIDetailAction(icon: "text.quote", label: "Summarize") {
                sendMessage("Summarize the note \"\(title)\"")
            })
            list.append(AIDetailAction(icon: "tag", label: "Suggest Tags") {
                sendMessage("What tags would you suggest for the note \"\(title)\"?")
            })
        }

        if let title = eventTitle {
            list.append(AIDetailAction(icon: "info.circle", label: "Details") {
                sendMessage("Tell me about the event \"\(title)\"")
            })
        }

        if let name = contactName {
            list.append(AIDetailAction(icon: "info.circle", label: "Details") {
                sendMessage("Tell me about the contact \"\(name)\"")
            })
        }

        if let title = todoTitle {
            list.append(AIDetailAction(icon: "info.circle", label: "Details") {
                sendMessage("Tell me about the todo \"\(title)\"")
            })
        }

        if let name = folderName {
            list.append(AIDetailAction(icon: "folder.badge.gearshape", label: "Organize") {
                sendMessage("How should I organize the items in the \"\(name)\" folder?")
            })
            list.append(AIDetailAction(icon: "list.bullet", label: "List Contents") {
                sendMessage("What's in the \"\(name)\" folder?")
            })
        }

        return list
    }

    private func sendMessage(_ message: String) {
        NotificationCenter.default.post(name: .showAIAssistantPanel, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AIAssistantViewModel.shared.send(message)
        }
    }
}

private struct AIDetailAction {
    let icon: String
    let label: String
    let execute: () -> Void
}
