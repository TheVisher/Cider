import SwiftUI
import UniformTypeIdentifiers

struct PinnedAppsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var pinnedAppsViewModel: PinnedAppsViewModel
    @EnvironmentObject var commandPaletteViewModel: CommandPaletteViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editingFolderID: UUID?
    @State private var editingFolderName: String = ""

    private var totalItems: Int {
        commandPaletteViewModel.totalPinnedItemCount
    }

    private var atCap: Bool {
        !commandPaletteViewModel.canAddMoreItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Pinned Apps") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Manage your pinned applications here.")
                            .font(.body)
                            .foregroundColor(CiderColors.secondary)

                        Spacer()

                        Text("\(totalItems) / \(CommandPaletteViewModel.maxPinnedItems)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(atCap ? CiderColors.destructive : CiderColors.secondary)
                    }

                    HStack(spacing: Spacing.md) {
                        Button(action: addApp) {
                            Label("Add App", systemImage: "plus")
                        }
                        .buttonStyle(SettingsButtonStyle())
                        .disabled(atCap)
                        .opacity(atCap ? 0.5 : 1.0)

                        Button(action: importDockApps) {
                            Label("Import from Dock", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(SettingsButtonStyle())
                        .disabled(atCap)
                        .opacity(atCap ? 0.5 : 1.0)
                    }

                    // Pinned apps list
                    if !pinnedAppsViewModel.apps.isEmpty {
                        VStack(spacing: Spacing.xs) {
                            ForEach(pinnedAppsViewModel.apps) { app in
                                PinnedAppRow(
                                    app: app,
                                    isRunning: pinnedAppsViewModel.isRunning(app),
                                    onRemove: { pinnedAppsViewModel.remove(app) }
                                )
                            }
                        }
                    }
                }
            }

            SettingsSection(title: "Folders") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Drag one app onto another in the command palette to create a folder.")
                        .font(.body)
                        .foregroundColor(CiderColors.secondary)

                    if commandPaletteViewModel.folders.isEmpty {
                        Text("No folders yet")
                            .font(.body)
                            .foregroundColor(CiderColors.tertiary)
                            .italic()
                    } else {
                        VStack(spacing: Spacing.xs) {
                            ForEach(commandPaletteViewModel.folders) { folder in
                                FolderSettingsRow(
                                    folder: folder,
                                    isEditing: editingFolderID == folder.id,
                                    editingName: editingFolderID == folder.id ? $editingFolderName : .constant(""),
                                    onStartEditing: {
                                        editingFolderID = folder.id
                                        editingFolderName = folder.name
                                    },
                                    onCommitRename: {
                                        if !editingFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                                            commandPaletteViewModel.renameFolder(folder, to: editingFolderName)
                                        }
                                        editingFolderID = nil
                                    },
                                    onDelete: {
                                        commandPaletteViewModel.deleteFolder(folder)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func addApp() {
        guard !atCap else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.level = .floating

        let response = panel.runModal()
        guard response == .OK else { return }
        for url in panel.urls {
            guard commandPaletteViewModel.canAddMoreItems else { break }
            pinnedAppsViewModel.addApp(from: url)
        }
    }

    private func importDockApps() {
        guard !atCap else { return }
        // Import respects the cap through the addApp flow
        pinnedAppsViewModel.importDockApps()
    }
}

// MARK: - Pinned App Row

private struct PinnedAppRow: View {
    let app: AppInfo
    let isRunning: Bool
    let onRemove: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 24, height: 24)

            Text(app.name)
                .font(.body)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            if isRunning {
                Circle()
                    .fill(CiderColors.success)
                    .frame(width: 6, height: 6)
            }

            Spacer()

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove \(app.name)")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
    }

    private var appIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }
}

// MARK: - Folder Settings Row

private struct FolderSettingsRow: View {
    let folder: AppFolder
    let isEditing: Bool
    @Binding var editingName: String
    let onStartEditing: () -> Void
    let onCommitRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundColor(CiderColors.secondary)
                .frame(width: 24, height: 24)

            if isEditing {
                TextField("Folder name", text: $editingName, onCommit: onCommitRename)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(CiderColors.primary)
            } else {
                Text(folder.name)
                    .font(.body)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
            }

            Text("\(folder.apps.count) apps")
                .font(.caption)
                .foregroundColor(CiderColors.tertiary)

            Spacer()

            if isHovering {
                HStack(spacing: Spacing.xs) {
                    Button(action: onStartEditing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename folder")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(CiderColors.destructive)
                    }
                    .buttonStyle(.plain)
                    .help("Delete folder (apps return to pinned list)")
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? .none : .snappy) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Settings Button Style

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.05))
            )
    }
}
