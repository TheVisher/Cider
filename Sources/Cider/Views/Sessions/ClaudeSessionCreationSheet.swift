import SwiftUI
import AppKit

/// Sheet for creating a new Claude Code session with a name and project folder.
struct ClaudeSessionCreationSheet: View {
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    @State private var sessionName = ""
    @State private var projectPath = ""
    @State private var recentProjects: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("New Session")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            // Name field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Name")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                TextField("Session name", text: $sessionName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceElevated)
                    )
            }

            // Folder picker
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Project Folder")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)

                HStack(spacing: Spacing.sm) {
                    Text(projectPath.isEmpty ? "Select a folder..." : projectPath)
                        .font(CiderFont.body)
                        .foregroundColor(projectPath.isEmpty ? CiderColors.tertiary : CiderColors.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Browse") { pickFolder() }
                        .buttonStyle(.plain)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.controlAccent)
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceElevated)
                )
            }

            // Recent projects
            if !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Recent Projects")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(recentProjects, id: \.absoluteString) { url in
                        Button {
                            projectPath = url.path
                            if sessionName.isEmpty {
                                sessionName = url.lastPathComponent
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                Text(url.lastPathComponent)
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(url.deletingLastPathComponent().path)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack {
                Spacer()

                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.secondary)

                Button("Create") { create() }
                    .buttonStyle(.plain)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .disabled(projectPath.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 400, height: 400)
        .onAppear { loadRecentProjects() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a project directory for the Claude session"

        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            if sessionName.isEmpty {
                sessionName = url.lastPathComponent
            }
        }
    }

    private func create() {
        let name = sessionName.isEmpty ? URL(fileURLWithPath: projectPath).lastPathComponent : sessionName
        onCreate(name, projectPath)
    }

    private func loadRecentProjects() {
        // Scan home directory for directories with .git or CLAUDE.md
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Developer", "Projects", "Code", "repos", "src", "workspace"]
        var found: [URL] = []

        for candidate in candidates {
            let dir = home.appendingPathComponent(candidate)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
            ) else { continue }

            for item in contents {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let hasGit = FileManager.default.fileExists(atPath: item.appendingPathComponent(".git").path)
                let hasClaudeMD = FileManager.default.fileExists(atPath: item.appendingPathComponent("CLAUDE.md").path)
                if hasGit || hasClaudeMD {
                    found.append(item)
                }
                if found.count >= 8 { break }
            }
            if found.count >= 8 { break }
        }

        recentProjects = found
    }
}
