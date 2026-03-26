import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var trashItems: [TrashItem] = []

    private let retentionOptions: [(label: String, days: Int)] = [
        ("7 days", 7),
        ("30 days", 30),
        ("90 days", 90),
        ("Never", 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Trash") {
                retentionRow
                Divider().opacity(CiderColors.dividerSecondaryOpacity)
                trashContents
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { loadTrashItems() }
        .onReceive(NotificationCenter.default.publisher(for: .trashContentsChanged)) { _ in
            loadTrashItems()
        }
    }

    private var retentionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Keep deleted items for")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                Text("Items older than this will be auto-removed on next launch")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            Spacer()

            Picker("", selection: $viewModel.trashRetentionDays) {
                ForEach(retentionOptions, id: \.days) { option in
                    Text(option.label).tag(option.days)
                }
            }
            .labelsHidden()
            .frame(width: SettingsDesign.retentionPickerWidth)
        }
    }

    @ViewBuilder
    private var trashContents: some View {
        if trashItems.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "trash")
                        .font(CiderFont.settingsEmptyIcon)
                        .foregroundColor(CiderColors.tertiary)
                    Text("Trash is empty")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(.vertical, Spacing.xl)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                let groupOrder: [(TrashItemType, String)] = [
                    (.bookmark, "Bookmarks"),
                    (.note, "Notes"),
                    (.dateCard, "Date Cards"),
                    (.contact, "Contacts"),
                    (.todo, "Todos"),
                    (.whiteboard, "Whiteboards"),
                    (.folder, "Folders"),
                    (.vaultFolder, "Folders"),
                    (.session, "Sessions"),
                    (.kanbanBoard, "Boards"),
                ]

                ForEach(groupOrder, id: \.0) { itemType, label in
                    let items = trashItems.filter { $0.itemType == itemType }
                    if !items.isEmpty {
                        Text(label)
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.secondary)
                            .padding(.top, Spacing.xs)

                        ForEach(items) { item in
                            TrashItemRow(item: item, onRestore: {
                                TrashStorage.shared.restore(item)
                                loadTrashItems()
                            }, onDelete: {
                                TrashStorage.shared.permanentlyDelete(item)
                                loadTrashItems()
                            })
                        }
                    }
                }

                HStack {
                    Text("\(trashItems.count) item\(trashItems.count == 1 ? "" : "s") in Trash")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    Spacer()

                    Button("Empty Trash") {
                        viewModel.showEmptyTrashConfirm = true
                    }
                    .buttonStyle(CiderDestructiveButtonStyle())
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func loadTrashItems() {
        trashItems = TrashStorage.shared.allTrashItems()
    }
}

private struct TrashItemRow: View {
    let item: TrashItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var trashItemIcon: String {
        switch item.itemType {
        case .bookmark: return "bookmark"
        case .note: return "note.text"
        case .dateCard: return "calendar"
        case .contact: return "person.crop.circle"
        case .todo: return "checklist"
        case .whiteboard: return "scribble"
        case .folder: return "folder"
        case .vaultFolder: return "folder"
        case .session: return "globe"
        case .kanbanBoard: return "square.split.2x1"
        case .vaultFile: return "doc"
        }
    }

    private var deletedAgoText: String {
        let interval = Date().timeIntervalSince(item.deletedAt)
        let days = Int(interval / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: trashItemIcon)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .frame(width: SettingsDesign.trashIconColumnWidth)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text("Deleted \(deletedAgoText)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            Spacer()

            Button("Restore") {
                onRestore()
            }
            .controlSize(.small)

            Button("Delete") {
                onDelete()
            }
            .controlSize(.small)
            .foregroundColor(CiderColors.destructive)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
