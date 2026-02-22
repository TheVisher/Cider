import SwiftUI
import AppKit

struct StorageSettingsView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    @State private var trashItems: [TrashItem] = []
    @State private var showEmptyTrashConfirm = false

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
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $showEmptyTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                TrashStorage.shared.emptyTrash()
                loadTrashItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All items in the trash will be permanently deleted. This cannot be undone.")
        }
    }

    private var retentionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
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
            .frame(width: 100)
        }
    }

    @ViewBuilder
    private var trashContents: some View {
        if trashItems.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "trash")
                        .font(.system(size: 28))
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
                let bookmarkItems = trashItems.filter { $0.itemType == .bookmark }
                let noteItems = trashItems.filter { $0.itemType == .note }
                let dateCardItems = trashItems.filter { $0.itemType == .dateCard }
                let contactItems = trashItems.filter { $0.itemType == .contact }

                if !bookmarkItems.isEmpty {
                    Text("Bookmarks")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.top, Spacing.xs)

                    ForEach(bookmarkItems) { item in
                        TrashItemRow(item: item, onRestore: {
                            TrashStorage.shared.restore(item)
                            loadTrashItems()
                        }, onDelete: {
                            TrashStorage.shared.permanentlyDelete(item)
                            loadTrashItems()
                        })
                    }
                }

                if !noteItems.isEmpty {
                    Text("Notes")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.top, Spacing.xs)

                    ForEach(noteItems) { item in
                        TrashItemRow(item: item, onRestore: {
                            TrashStorage.shared.restore(item)
                            loadTrashItems()
                        }, onDelete: {
                            TrashStorage.shared.permanentlyDelete(item)
                            loadTrashItems()
                        })
                    }
                }

                if !dateCardItems.isEmpty {
                    Text("Date Cards")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.top, Spacing.xs)

                    ForEach(dateCardItems) { item in
                        TrashItemRow(item: item, onRestore: {
                            TrashStorage.shared.restore(item)
                            loadTrashItems()
                        }, onDelete: {
                            TrashStorage.shared.permanentlyDelete(item)
                            loadTrashItems()
                        })
                    }
                }

                if !contactItems.isEmpty {
                    Text("Contacts")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.top, Spacing.xs)

                    ForEach(contactItems) { item in
                        TrashItemRow(item: item, onRestore: {
                            TrashStorage.shared.restore(item)
                            loadTrashItems()
                        }, onDelete: {
                            TrashStorage.shared.permanentlyDelete(item)
                            loadTrashItems()
                        })
                    }
                }

                HStack {
                    Text("\(trashItems.count) item\(trashItems.count == 1 ? "" : "s") in Trash")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)

                    Spacer()

                    Button("Empty Trash") {
                        showEmptyTrashConfirm = true
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
        case .folder: return "folder"
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
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
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
