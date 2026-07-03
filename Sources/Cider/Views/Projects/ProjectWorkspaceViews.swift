import AppKit
import SwiftUI

struct ProjectWorkspaceOverviewView: View {
    let model: ProjectWorkspaceOverviewModel
    var onOpenProject: (ProjectWorkspaceProjectRow) -> Void
    var onOpenBoard: (String) -> Void
    var onOpenMilestoneBoard: (ProjectWorkspaceMilestoneRow) -> Void = { _ in }
    var onOpenMilestoneArtifact: (ProjectWorkspaceMilestoneArtifactLink) -> Void = { _ in }
    var onCreateBoard: () -> Void

    @State private var selectedCoreDoc: ProjectWorkspaceCoreDocRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                statusStrip
                if !model.resources.isEmpty {
                    resourcesSection
                }
                if model.latestUpdate != nil {
                    latestUpdateSection
                }
                if !model.milestoneRows.isEmpty {
                    milestoneSection
                }
                if !model.recentArtifacts.isEmpty {
                    recentArtifactsSection
                }
                if !model.projectRows.isEmpty {
                    projectSection
                }
                boardSection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedCoreDoc) { artifact in
            ProjectWorkspaceCoreDocPreview(artifact: artifact)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(model.workspace.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
            Text(model.workspace.subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: Spacing.sm) {
            metricChip("Queued", value: model.totals.queued, symbol: "tray")
            metricChip("In Progress", value: model.totals.inProgress, symbol: "hammer")
            metricChip("Testing", value: model.totals.testing, symbol: "checklist")
            metricChip("Blocked", value: model.totals.blocked, symbol: "exclamationmark.triangle")
            Spacer(minLength: 0)
        }
    }

    private func metricChip(_ title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text("\(value)")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
            Text(title)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline)
        )
    }

    private var resourcesSection: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text("Resources")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 86, alignment: .leading)

            HStack(spacing: Spacing.xs) {
                ForEach(model.resources) { resource in
                    resourceLink(resource)
                }

                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Add resource")
            }

            Spacer(minLength: 0)
        }
    }

    private func resourceLink(_ resource: ProjectWorkspaceResourceRow) -> some View {
        Button {
            NSWorkspace.shared.open(resource.url)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: resource.systemImage)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Text(resource.title)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(resource.url.absoluteString)
    }

    private var latestUpdateSection: some View {
        overviewSection("Latest Update") {
            if let update = model.latestUpdate {
                Button {
                    onOpenBoard(update.boardID)
                } label: {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: update.symbolName)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.controlAccent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text(update.typeLabel)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.primary)
                                Text(update.cardDisplayKey)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.controlAccent)
                                Text(Self.updateDateFormatter.string(from: update.createdAt))
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            Text(update.cardTitle)
                                .font(CiderFont.bodySemibold)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)
                            Text(update.body)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .overviewRow()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var milestoneSection: some View {
        overviewSection("Milestones") {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(model.milestoneRows) { row in
                    milestoneRow(row)
                }
            }
        }
    }

    private func milestoneRow(_ row: ProjectWorkspaceMilestoneRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "diamond")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(row.cardDisplayKey)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.controlAccent)
                        Text(row.status)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                        Text("\(row.childCount) \(row.childCount == 1 ? "card" : "cards")")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Text(row.title.replacingOccurrences(of: "Milestone: ", with: ""))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if !row.description.isEmpty {
                        Text(row.description)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Spacing.sm)

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("\(row.completedChildCount)/\(row.childCount)")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)
                    Text("\(Int((row.progressFraction * 100).rounded()))%")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .frame(width: 48, alignment: .trailing)
            }

            ProgressView(value: row.progressFraction)
                .progressViewStyle(.linear)
                .controlSize(.small)

            HStack(spacing: Spacing.xs) {
                ForEach(row.artifactLinks.prefix(3)) { link in
                    Button {
                        onOpenMilestoneArtifact(link)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: link.artifactType.localizedLowercase == "plan" ? "doc.text" : "checklist")
                                .font(CiderFont.micro)
                            Text(link.displayType)
                                .font(CiderFont.captionSemibold)
                        }
                        .foregroundColor(CiderColors.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(CiderColors.surfaceInput))
                    }
                    .buttonStyle(.plain)
                    .help(link.title)
                }

                Spacer(minLength: 0)

                Button {
                    onOpenMilestoneBoard(row)
                } label: {
                    HStack(spacing: 4) {
                        Text("Show cards")
                            .font(CiderFont.captionSemibold)
                        Image(systemName: "arrow.right")
                            .font(CiderFont.micro)
                    }
                    .foregroundColor(CiderColors.controlAccent)
                }
                .buttonStyle(.plain)
                .help("Open \(row.boardName) filtered to this milestone")
            }

        }
        .overviewRow()
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenMilestoneBoard(row)
        }
    }

    private var recentArtifactsSection: some View {
        overviewSection("Artifacts") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(model.recentArtifacts) { artifact in
                    coreDocCard(artifact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func coreDocCard(_ artifact: ProjectWorkspaceCoreDocRow) -> some View {
        Button {
            selectedCoreDoc = artifact
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "doc.text")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.title)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                        Text(artifact.relativePath)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                }

                HStack(spacing: Spacing.xs) {
                    metadataPill(Self.shortDateFormatter.string(from: artifact.modifiedAt))
                    metadataPill("\(artifact.lineCount) lines")
                    metadataPill("\(artifact.wordCount) words")
                }
            }
            .overviewRow()
        }
        .buttonStyle(.plain)
        .help(artifact.fileURL.path)
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.micro)
            .foregroundColor(CiderColors.secondary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput.opacity(0.78))
            )
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Active Projects")
            LazyVStack(spacing: Spacing.xs) {
                ForEach(model.projectRows) { row in
                    Button {
                        onOpenProject(row)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "shippingbox")
                                .foregroundColor(CiderColors.tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(CiderFont.bodySemibold)
                                    .foregroundColor(CiderColors.primary)
                                Text("\(row.totals.inProgress) active · \(row.totals.testing) testing · \(row.totals.blocked) blocked")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.tertiary)
                        }
                        .padding(Spacing.md)
                        .sectionContainer(cornerRadius: Radius.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                sectionTitle("Related Boards")
                Spacer(minLength: 0)
                if let actionTitle = model.boardCreationActionTitle {
                    Button {
                        onCreateBoard()
                    } label: {
                        Label(actionTitle, systemImage: "plus")
                            .font(CiderFont.captionSemibold)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Create a board in \(model.workspace.title)")
                }
            }
            if model.boardSummaries.isEmpty {
                EmptyStateView(
                    icon: "square.split.2x1",
                    title: "No project boards yet",
                    subtitle: "Browse remains available for unscoped boards."
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(model.boardSummaries) { summary in
                        Button {
                            onOpenBoard(summary.boardID)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "square.split.2x1")
                                    .foregroundColor(CiderColors.tertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.boardName)
                                        .font(CiderFont.bodySemibold)
                                        .foregroundColor(CiderColors.primary)
                                    Text("\(summary.totals.queued) queued · \(summary.totals.inProgress) active · \(summary.totals.testing) testing")
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .padding(Spacing.md)
                            .sectionContainer(cornerRadius: Radius.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.tertiary)
    }

    private func overviewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle(title)
            content()
        }
    }

    private static let updateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension View {
    func overviewRow() -> some View {
        self
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(CiderColors.borderSubtle, lineWidth: Spacing.hairline)
            )
    }
}

struct ProjectWorkspaceSurfacePlaceholderView: View {
    let project: ProjectWorkspace
    let surface: ProjectWorkspaceSurface

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(surface.title, systemImage: surface.systemImage)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text("\(project.title) workspace")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
            }

            EmptyStateView(
                icon: surface.systemImage,
                title: "\(surface.title) surface is ready",
                subtitle: surface.placeholderSubtitle
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProjectWorkspaceCoreDocPreview: View {
    let artifact: ProjectWorkspaceCoreDocRow

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(CiderColors.surfaceElevated)

            Divider()
                .overlay(CiderColors.borderSubtle)

            Group {
                if let errorMessage {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Could not open doc",
                        subtitle: errorMessage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(content)
                            .font(CiderFont.monospacedBody)
                            .foregroundColor(CiderColors.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.lg)
                    }
                    .scrollIndicators(.visible)
                    .background(CiderColors.opaqueBackground)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 640)
        .task(id: artifact.id) {
            loadContent()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: "doc.text")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                Text("\(artifact.relativePath) · \(artifact.lineCount) lines · \(artifact.wordCount) words")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.md)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([artifact.fileURL])
            } label: {
                Image(systemName: "folder")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
    }

    private func loadContent() {
        do {
            content = try String(contentsOf: artifact.fileURL, encoding: .utf8)
            errorMessage = nil
        } catch {
            content = ""
            errorMessage = error.localizedDescription
        }
    }
}

struct ProjectWorkspaceMilestonesView: View {
    let workspace: ProjectWorkspace
    let milestones: [ProjectWorkspaceMilestoneRow]
    var onOpenMilestoneBoard: (ProjectWorkspaceMilestoneRow) -> Void
    var onOpenMilestoneArtifact: (ProjectWorkspaceMilestoneArtifactLink) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header

            if milestones.isEmpty {
                EmptyStateView(
                    icon: ProjectWorkspaceSurface.milestones.systemImage,
                    title: "No milestones yet",
                    subtitle: ProjectWorkspaceSurface.milestones.placeholderSubtitle
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(milestones) { milestone in
                            milestoneRow(milestone)
                        }
                    }
                    .padding(.bottom, Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Milestones", systemImage: ProjectWorkspaceSurface.milestones.systemImage)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text("Overarching goals for \(workspace.title), with child-card progress and linked planning/QA artifacts.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
            }
            Spacer(minLength: 0)
            Text("\(milestones.count)")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
        }
    }

    private func milestoneRow(_ row: ProjectWorkspaceMilestoneRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "diamond")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(row.cardDisplayKey)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.controlAccent)
                        Text(row.status)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                        Text("\(row.childCount) \(row.childCount == 1 ? "card" : "cards")")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Text(row.title.replacingOccurrences(of: "Milestone: ", with: ""))
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if !row.description.isEmpty {
                        Text(row.description)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Spacing.sm)

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("\(row.completedChildCount)/\(row.childCount)")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.primary)
                    Text("\(Int((row.progressFraction * 100).rounded()))%")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .frame(width: 56, alignment: .trailing)
            }

            ProgressView(value: row.progressFraction)
                .progressViewStyle(.linear)
                .controlSize(.small)

            HStack(spacing: Spacing.xs) {
                ForEach(row.artifactLinks.prefix(4)) { link in
                    Button {
                        onOpenMilestoneArtifact(link)
                    } label: {
                        Label(link.displayType, systemImage: link.artifactType.localizedLowercase == "plan" ? "doc.text" : "checklist")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.secondary)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(CiderColors.surfaceInput))
                    }
                    .buttonStyle(.plain)
                    .help(link.title)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("Show cards")
                        .font(CiderFont.captionSemibold)
                    Image(systemName: "arrow.right")
                        .font(CiderFont.micro)
                }
                .foregroundColor(CiderColors.controlAccent)
            }
        }
        .overviewRow()
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenMilestoneBoard(row)
        }
    }
}

struct ProjectWorkspaceSurfaceView: View {
    let model: ProjectWorkspaceSurfaceModel
    var allNotes: [Note]? = nil
    var artifactRelations: [SecondBrainRelation] = []
    var onOpenNote: (Note) -> Void

    @State private var displayMode: ProjectWorkspaceSurfaceDisplayMode = .list
    @State private var planScope: ProjectPlanScope = .active

    private var currentModel: ProjectWorkspaceSurfaceModel {
        guard model.surface == .plansHandoffs, let allNotes else { return model }
        return ProjectWorkspaceSurfaceProvider.model(
            for: model.workspace,
            surface: model.surface,
            notes: allNotes,
            artifactRelations: artifactRelations,
            planScope: planScope
        )
    }

    var body: some View {
        if currentModel.surface.usesProjectArtifactList {
            artifactListBody
        } else {
            ProjectWorkspaceSurfacePlaceholderView(project: currentModel.workspace, surface: currentModel.surface)
        }
    }

    private var artifactListBody: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header

            if currentModel.notes.isEmpty {
                EmptyStateView(
                    icon: currentModel.surface.systemImage,
                    title: emptyTitle,
                    subtitle: currentModel.surface.placeholderSubtitle
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    artifactContent
                        .padding(.bottom, Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(currentModel.surface.title, systemImage: currentModel.surface.systemImage)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text(surfaceSubtitle)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.sm) {
                if currentModel.surface == .plansHandoffs {
                    planScopeControls
                }
                displayModeControls
            }
            .padding(.top, 2)
        }
    }

    private var planScopeControls: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ProjectPlanScope.allCases) { scope in
                planScopeChip(scope)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan scope")
    }

    private func planScopeChip(_ scope: ProjectPlanScope) -> some View {
        let isSelected = planScope == scope
        return Button {
            planScope = scope
        } label: {
            Label(scope.title, systemImage: scope.systemImage)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.accentSubtle : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
        .help("Show \(scope.title.lowercased()) plans")
    }

    private var displayModeControls: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ProjectWorkspaceSurfaceDisplayMode.allCases) { mode in
                displayModeChip(mode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View mode")
    }

    private func displayModeChip(_ mode: ProjectWorkspaceSurfaceDisplayMode) -> some View {
        let isSelected = displayMode == mode
        return Button {
            displayMode = mode
        } label: {
            Label(mode.title, systemImage: mode.systemImage)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
        .help("Show \(currentModel.surface.title) as \(mode.title.lowercased())")
    }

    @ViewBuilder
    private var artifactContent: some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xs) {
                ForEach(currentModel.notes) { row in
                    noteListRow(row)
                }
            }
        case .grid:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(currentModel.notes) { row in
                    noteGridCard(row)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func noteListRow(_ row: ProjectWorkspaceNoteRow) -> some View {
        Button {
            onOpenNote(row.note)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: currentModel.surface.systemImage)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                    if !row.preview.isEmpty {
                        Text(row.preview)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(2)
                    }
                    noteMetadata(row, pathLineLimit: 1, relationLineLimit: 1)
                }
                Spacer(minLength: 0)
                Text(row.owner.canonicalRef)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }
            .padding(Spacing.md)
            .sectionContainer(cornerRadius: Radius.sm)
        }
        .buttonStyle(.plain)
    }

    private func noteGridCard(_ row: ProjectWorkspaceNoteRow) -> some View {
        Button {
            onOpenNote(row.note)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: currentModel.surface.systemImage)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(CiderColors.accentSubtle)
                        )
                    Spacer(minLength: 0)
                    Text(row.owner.canonicalRef)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Text(row.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !row.preview.isEmpty {
                    Text(row.preview)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                noteMetadata(row, pathLineLimit: 2, relationLineLimit: 2)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
            .sectionContainer(cornerRadius: Radius.md)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func noteMetadata(_ row: ProjectWorkspaceNoteRow, pathLineLimit: Int, relationLineLimit: Int) -> some View {
        if let planMetadata = row.planMetadata {
            planMetadataChips(planMetadata)
        }
        Text(row.path)
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
            .lineLimit(pathLineLimit)
        if !row.relationSummary.isEmpty {
            Text(row.relationSummary)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.controlAccent)
                .lineLimit(relationLineLimit)
        }
    }

    private func planMetadataChips(_ metadata: ProjectPlanMetadata) -> some View {
        HStack(spacing: Spacing.xs) {
            metadataChip(metadata.type)
            metadataChip(metadata.status)
            if let category = metadata.category {
                metadataChip(category)
            }
            if let dogfoodStatus = metadata.dogfoodStatus {
                metadataChip(dogfoodStatus)
            }
            if let source = metadata.source {
                metadataChip(source)
            }
        }
        .lineLimit(1)
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.separatorLight)
            )
    }

    private var surfaceSubtitle: String {
        switch currentModel.surface {
        case .notes:
            return "Markdown-backed notes stored under Projects/\(currentModel.workspace.title)/Notes"
        case .plansHandoffs:
            return "Draft feature plans stored under Projects/\(currentModel.workspace.title)/Plans until they become milestones and cards"
        case .decisions:
            return "Durable decisions stored under Projects/\(currentModel.workspace.title)/Decisions"
        case .qaAudits:
            return "Audit results and QA reports stored under Projects/\(currentModel.workspace.title)/QA until they become cleanup milestones and cards"
        default:
            return currentModel.surface.placeholderSubtitle
        }
    }

    private var emptyTitle: String {
        switch currentModel.surface {
        case .notes:
            return "No project notes yet"
        case .plansHandoffs:
            return "No plans yet"
        case .decisions:
            return "No decisions yet"
        case .qaAudits:
            return "No QA audits yet"
        default:
            return "No project artifacts yet"
        }
    }
}

struct ProjectReferencesView: View {
    let project: ProjectWorkspace
    let references: [ProjectReferenceItem]
    let boards: [KanbanBoard]
    var onOpenItem: (LibraryItemV2) -> Void
    var onOpenCard: (String, String) -> Void
    var onLinkReferenceToCard: (LibraryEntityRef, String, String) -> Void
    var onPromoteReference: (ProjectReferenceItem) -> Void

    private var cardCandidates: [ProjectReferenceCardCandidate] {
        boards
            .filter { project.boardIDs.contains($0.id) }
            .flatMap { board in
                board.columns.flatMap { column in
                    column.cards.map { card in
                        ProjectReferenceCardCandidate(
                            boardID: board.id,
                            boardName: board.name,
                            columnName: column.name,
                            card: card
                        )
                    }
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.md)

            if references.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "No scoped references yet",
                    subtitle: "Items placed in Projects/\(project.title)/Assets will appear here. Library and Browse still have everything else."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(references) { reference in
                            referenceRow(reference)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(project.title) References")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
            Text("Saved URLs, screenshots, notes, files, and inspiration that can feed project work.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
        }
    }

    private func referenceRow(_ reference: ProjectReferenceItem) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                onOpenItem(reference.item)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: symbol(for: reference.item.entityType))
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.item.title)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                        Text(reference.reason)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Menu {
                if !cardCandidates.isEmpty {
                    Menu("Link to Card") {
                        ForEach(cardCandidates) { candidate in
                            Button("\(candidate.card.title) · \(candidate.boardName)") {
                                onLinkReferenceToCard(reference.ref, candidate.boardID, candidate.card.id)
                            }
                        }
                    }
                }
                Button("Promote to Card") {
                    onPromoteReference(reference)
                }
                if reference.linkedCardCount > 0 {
                    Divider()
                    ForEach(cards(linking: reference.ref)) { candidate in
                        Button("Open \(candidate.card.title)") {
                            onOpenCard(candidate.boardID, candidate.card.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(Spacing.md)
        .sectionContainer(cornerRadius: Radius.sm)
    }

    private func cards(linking ref: LibraryEntityRef) -> [ProjectReferenceCardCandidate] {
        cardCandidates.filter { $0.card.linkedEntities.contains(ref) }
    }

    private func symbol(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark: return "bookmark"
        case .note: return "note.text"
        case .dateCard: return "calendar"
        case .contact: return "person.crop.circle"
        case .todo: return "checklist"
        case .vaultFile: return "doc"
        case .externalFile: return "doc"
        case .session: return "bubble.left.and.bubble.right"
        }
    }
}

private struct ProjectReferenceCardCandidate: Identifiable {
    let boardID: String
    let boardName: String
    let columnName: String
    let card: KanbanCard

    var id: String { "\(boardID)-\(card.id)" }
}
