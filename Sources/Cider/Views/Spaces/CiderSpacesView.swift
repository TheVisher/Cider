import SwiftUI

struct CiderSpaceOverviewView: View {
    let space: CiderSpace
    let rootURL: URL
    let captureDashboard: CiderSpaceCaptureDashboard?
    let bookmarks: [Bookmark]
    let mediaItems: [MediaItem]
    let notes: [Note]
    let onTogglePinned: () -> Void
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void

    var body: some View {
        switch space.preset {
        case .media:
            MediaSpaceDashboardView(
                space: space,
                rootURL: rootURL,
                captureDashboard: captureDashboard,
                bookmarks: bookmarks,
                mediaItems: mediaItems,
                notes: notes,
                onTogglePinned: onTogglePinned,
                onOpenBookmark: onOpenBookmark,
                onOpenNote: onOpenNote
            )
        case .recipes:
            RecipeSpaceDashboardView(
                space: space,
                rootURL: rootURL,
                captureDashboard: captureDashboard,
                bookmarks: bookmarks,
                notes: notes,
                onTogglePinned: onTogglePinned,
                onOpenBookmark: onOpenBookmark,
                onOpenNote: onOpenNote
            )
        default:
            genericOverview
        }
    }

    private var genericOverview: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - (Spacing.md * 2)), HomeOverviewDesign.maxContentWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                    overviewPanel
                    captureRoutingPanel
                    defaultViewsPanel
                    instructionsPanel
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, HomeOverviewDesign.telemetryTopPadding)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var overviewPanel: some View {
        HomeOverviewPanel(
            title: "Space",
            headerAccessory: AnyView(
                Button {
                    onTogglePinned()
                } label: {
                    Label(space.isPinned ? "Pinned" : "Unpinned", systemImage: space.isPinned ? "pin.fill" : "pin")
                        .font(CiderFont.captionSemibold)
                }
                .buttonStyle(.plain)
                .foregroundColor(space.isPinned ? CiderColors.controlAccent : CiderColors.tertiary)
            )
        ) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: space.systemImage)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(space.name)
                        .font(CiderFont.displayBold)
                        .foregroundColor(CiderColors.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(space.purpose)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .background(CiderColors.separator)
                .padding(.vertical, Spacing.xs)

            metadataRow(title: "Preset", value: space.preset.displayName)
            metadataRow(title: "Vault path", value: space.rootRelativePath)
            metadataRow(title: "Finder folder", value: rootURL.path)
        }
    }

    @ViewBuilder
    private var captureRoutingPanel: some View {
        if let captureDashboard, captureDashboard.hasItems {
            CiderSpaceCaptureRoutingPanel(
                dashboard: captureDashboard,
                bookmarks: bookmarks,
                onOpenBookmark: onOpenBookmark
            )
        }
    }

    private var defaultViewsPanel: some View {
        HomeOverviewPanel(title: "Starter Views") {
            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(space.defaultViews, id: \.self) { view in
                    Label(view.displayName, systemImage: view.systemImage)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.secondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(CiderColors.surfaceInput)
                        )
                }
            }

            Text("These are starter views for the Space. They describe the shape of the context without building a custom dashboard yet.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var instructionsPanel: some View {
        HomeOverviewPanel(title: "AI Routing") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Instructions")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .tracking(1.2)

                    Text(space.aiInstructions)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !space.routingHints.isEmpty {
                    Divider()
                        .background(CiderColors.separator)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Hints")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.tertiary)
                            .tracking(1.2)

                        ForEach(space.routingHints, id: \.self) { hint in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)

                                Text(hint)
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.2)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
    }
}

struct CiderSpaceCaptureRoutingPanel: View {
    let dashboard: CiderSpaceCaptureDashboard
    let bookmarks: [Bookmark]
    let onOpenBookmark: (Bookmark) -> Void

    private var bookmarksByID: [UUID: Bookmark] {
        Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            if !dashboard.needsReview.isEmpty {
                HomeOverviewPanel(title: "Routing Review") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(dashboard.needsReview.prefix(6))) { item in
                            captureRow(item, tone: .review)
                        }
                    }
                }
            }

            if !dashboard.recentRouted.isEmpty {
                HomeOverviewPanel(title: "Recent Routed Captures") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(dashboard.recentRouted.prefix(6))) { item in
                            captureRow(item, tone: .accepted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func captureRow(_ item: CiderSpaceCaptureDashboardItem, tone: CaptureRowTone) -> some View {
        if let bookmark = bookmarksByID[item.itemID] {
            Button {
                onOpenBookmark(bookmark)
            } label: {
                captureRowContent(item, tone: tone)
            }
            .buttonStyle(.plain)
        } else {
            captureRowContent(item, tone: tone)
        }
    }

    private func captureRowContent(_ item: CiderSpaceCaptureDashboardItem, tone: CaptureRowTone) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: tone.systemImage)
                .font(CiderFont.bodyMedium)
                .foregroundColor(tone.color)
                .frame(width: Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(item.title)
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(item.reviewState.replacingOccurrences(of: "_", with: " "))
                        .font(CiderFont.microBold)
                        .foregroundColor(tone.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.hairline)
                        .background(Capsule(style: .continuous).fill(tone.color.opacity(0.12)))
                }

                Text(item.reason)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Label(item.target.relativePath, systemImage: "folder")
                    Text("confidence \(formattedConfidence(item.confidence))")
                    if let sourceURL = item.sourceURL {
                        Text(sourceHost(sourceURL))
                    }
                }
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func formattedConfidence(_ confidence: Double) -> String {
        let percent = Int((confidence * 100).rounded())
        return "\(percent)%"
    }

    private func sourceHost(_ rawURL: String) -> String {
        URL(string: rawURL)?.host ?? rawURL
    }

    private enum CaptureRowTone {
        case accepted
        case review

        var systemImage: String {
            switch self {
            case .accepted: "checkmark.circle"
            case .review: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .accepted: CiderColors.success
            case .review: CiderColors.warning
            }
        }
    }
}

extension CiderSpaceCaptureDashboard {
    var hasItems: Bool {
        !recentRouted.isEmpty || !needsReview.isEmpty
    }
}

struct CiderSpacesManagerView: View {
    let spaces: [CiderSpace]
    let loadIssues: [String]
    let onCreateSpace: (CiderSpacePresetKind) -> Void
    let onOpenSpace: (CiderSpace) -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - (Spacing.md * 2)), HomeOverviewDesign.maxContentWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                    createPanel
                    spacesPanel

                    if !loadIssues.isEmpty {
                        issuesPanel
                    }
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, HomeOverviewDesign.telemetryTopPadding)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var createPanel: some View {
        HomeOverviewPanel(title: "Create Space") {
            Text("Spaces are Finder-visible folders with Cider metadata, presets, AI instructions, routing hints, and starter views.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(CiderSpacePresetKind.allCases, id: \.self) { kind in
                    let preset = CiderSpacePreset.defaults(for: kind)

                    Button {
                        onCreateSpace(kind)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Image(systemName: preset.systemImage)
                                .font(CiderFont.bodySemibold)
                                .foregroundColor(CiderColors.controlAccent)

                            Text(preset.title)
                                .font(CiderFont.labelSemibold)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)

                            Text(preset.purpose)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(2)
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(CiderColors.surfaceInput)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var spacesPanel: some View {
        HomeOverviewPanel(title: "All Spaces") {
            if spaces.isEmpty {
                Text("No Spaces yet.")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("Create a preset above to add a real folder under Spaces/ with readable Cider metadata.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(spaces) { space in
                        Button {
                            onOpenSpace(space)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: space.systemImage)
                                    .font(CiderFont.bodyMedium)
                                    .foregroundColor(CiderColors.controlAccent)
                                    .frame(width: Spacing.xl, height: Spacing.xl)

                                VStack(alignment: .leading, spacing: Spacing.hairline) {
                                    HStack(spacing: Spacing.xs) {
                                        Text(space.name)
                                            .font(CiderFont.labelSemibold)
                                            .foregroundColor(CiderColors.primary)

                                        if space.isPinned {
                                            Image(systemName: "pin.fill")
                                                .font(CiderFont.micro)
                                                .foregroundColor(CiderColors.tertiary)
                                        }
                                    }

                                    Text(space.rootRelativePath)
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.quaternary)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var issuesPanel: some View {
        HomeOverviewPanel(title: "Load Issues") {
            ForEach(loadIssues, id: \.self) { issue in
                Text(issue)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension CiderSpacePresetKind {
    var displayName: String {
        CiderSpacePreset.defaults(for: self).title
    }
}

private extension CiderSpaceDefaultView {
    var displayName: String {
        switch self {
        case .overview: "Overview"
        case .inbox: "Inbox"
        case .recent: "Recent"
        case .notes: "Notes"
        case .files: "Files"
        case .tasks: "Tasks"
        case .events: "Events"
        case .boards: "Boards"
        case .references: "References"
        case .people: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .inbox: "tray"
        case .recent: "clock"
        case .notes: "note.text"
        case .files: "doc"
        case .tasks: "checklist"
        case .events: "calendar"
        case .boards: "rectangle.3.group"
        case .references: "photo.on.rectangle"
        case .people: "person.2"
        }
    }
}
