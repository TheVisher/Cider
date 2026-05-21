import SwiftUI

struct ProjectWorkspaceOverviewView: View {
    let model: ProjectWorkspaceOverviewModel
    var onOpenProject: (ProjectWorkspaceProjectRow) -> Void
    var onOpenBoard: (String) -> Void
    var onCreateBoard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                totalsGrid
                if !model.artifacts.isEmpty {
                    artifactSection
                }
                if !model.projectRows.isEmpty {
                    projectSection
                }
                boardSection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
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

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("Project Docs & Artifacts")
            LazyVStack(spacing: Spacing.xs) {
                ForEach(model.artifacts) { artifact in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: symbol(forArtifactOwner: artifact.owner))
                            .foregroundColor(CiderColors.tertiary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artifact.title)
                                .font(CiderFont.bodySemibold)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)
                            Text(artifact.evidence.isEmpty ? artifact.relationType : artifact.evidence)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(artifact.owner.canonicalRef)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                    .padding(Spacing.md)
                    .sectionContainer(cornerRadius: Radius.sm)
                    .help(artifact.safeCommand)
                }
            }
        }
    }

    private var totalsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: Spacing.sm)], spacing: Spacing.sm) {
            metric("Queued", value: model.totals.queued, symbol: "tray")
            metric("In Progress", value: model.totals.inProgress, symbol: "hammer")
            metric("Testing", value: model.totals.testing, symbol: "checklist")
            metric("Blocked", value: model.totals.blocked, symbol: "exclamationmark.triangle")
        }
    }

    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                Text(title)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .sectionContainer(cornerRadius: Radius.sm)
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

    private func symbol(forArtifactOwner owner: SecondBrainOwnerRef) -> String {
        switch owner.ownerType {
        case "note":
            return "note.text"
        case "kanban_card":
            return "rectangle.and.pencil.and.ellipsis"
        case "vaultFile":
            return "doc"
        default:
            return "link"
        }
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
                    subtitle: "Cider-related bookmarks, images, notes, files, and linked card references will appear here. Browse still has everything."
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
