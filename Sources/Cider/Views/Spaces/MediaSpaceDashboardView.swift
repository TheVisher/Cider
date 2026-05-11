import SwiftUI

struct MediaSpaceDashboardView: View {
    let space: CiderSpace
    let rootURL: URL
    let bookmarks: [Bookmark]
    let mediaItems: [MediaItem]
    let notes: [Note]
    let onTogglePinned: () -> Void
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void

    @State private var selectedSection: MediaSpaceSectionKind?
    @State private var selectedItem: MediaSpaceItem?
    @State private var model: MediaSpaceDashboardModel = .empty

    private var activeSection: MediaSpaceSectionKind? {
        selectedSection
    }

    private var modelSignature: MediaSpaceDashboardInputSignature {
        MediaSpaceDashboardInputSignature(
            bookmarks: bookmarks,
            mediaItems: mediaItems,
            notes: notes
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - (Spacing.md * 2)), HomeOverviewDesign.maxContentWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                    headerPanel
                    sectionFilterBar

                    if let selectedItem {
                        mediaItemDetailPanel(selectedItem)
                    }

                    if let activeSection {
                        sectionDetail(for: activeSection)
                    } else {
                        collectionMapPanel
                        mediaHealthPanel
                        recommendedActionsPanel
                        featuredShelfPanel
                        tasteProfilePanel
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
        .onAppear {
            rebuildModel()
        }
        .onChange(of: modelSignature) { _, _ in
            rebuildModel()
        }
    }

    private func rebuildModel() {
        model = MediaSpaceDashboardModel.make(
            bookmarks: bookmarks,
            mediaItems: mediaItems,
            notes: notes
        )
    }

    private var headerPanel: some View {
        HomeOverviewPanel(
            title: activeSection?.displayName ?? "Media Space",
            headerAccessory: AnyView(
                HStack(spacing: Spacing.sm) {
                    if selectedSection != nil {
                        Button {
                            selectSection(nil)
                        } label: {
                            Label("Overview", systemImage: "rectangle.grid.2x2")
                                .font(CiderFont.captionSemibold)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(CiderColors.secondary)
                    }

                    Button {
                        onTogglePinned()
                    } label: {
                        Label(space.isPinned ? "Pinned" : "Unpinned", systemImage: space.isPinned ? "pin.fill" : "pin")
                            .font(CiderFont.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(space.isPinned ? CiderColors.controlAccent : CiderColors.tertiary)
                }
            )
        ) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "play.rectangle")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(activeSection?.subtitle ?? "Movies, shows, games, books, music, and entertainment tracking.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.sm) {
                        mediaMetric("\(model.totalMediaItems)", label: "saved items")
                        mediaMetric("\(model.needsSortingCount)", label: "needs sorting")
                        mediaMetric("\(model.tasteSignals().count)", label: "taste signals")
                    }
                    .padding(.top, Spacing.xs)
                }
            }

            Text(rootURL.path)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var sectionFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                sectionFilterButton(title: "Overview", systemImage: "rectangle.grid.2x2", section: nil)

                ForEach(MediaSpaceSectionKind.allCases, id: \.self) { section in
                    let summary = model.summary(for: section)
                    sectionFilterButton(
                        title: "\(section.displayName) \(summary.count)",
                        systemImage: section.systemImage,
                        section: section
                    )
                }
            }
            .padding(.vertical, Spacing.hairline)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionFilterButton(
        title: String,
        systemImage: String,
        section: MediaSpaceSectionKind?
    ) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectSection(section)
        } label: {
            Label(title, systemImage: systemImage)
                .font(CiderFont.captionSemibold)
                .foregroundColor(isSelected ? CiderColors.textOnColor : CiderColors.secondary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.controlAccent : CiderColors.surfaceInput)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isSelected ? Color.clear : CiderColors.borderSubtle, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var collectionMapPanel: some View {
        HomeOverviewPanel(title: "Collection Map") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(MediaSpaceSectionKind.allCases, id: \.self) { section in
                    let summary = model.summary(for: section)

                    Button {
                        selectSection(section)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: section.systemImage)
                                    .font(CiderFont.bodySemibold)
                                    .foregroundColor(CiderColors.controlAccent)

                                Spacer(minLength: 0)

                                Text("\(summary.count)")
                                    .font(CiderFont.headingSemibold)
                                    .foregroundColor(CiderColors.primary)
                            }

                            Text(section.displayName)
                                .font(CiderFont.labelSemibold)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)

                            Text(section.subtitle)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(2)
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
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

    private var mediaHealthPanel: some View {
        HomeOverviewPanel(title: "Media Library Health") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: Spacing.xs)], spacing: Spacing.xs) {
                    mediaFact("Structured", value: "\(model.structuredItemCount)")
                    mediaFact("Source-only", value: "\(model.sourceOnlyItemCount)")
                    mediaFact("Needs sorting", value: "\(model.needsSortingCount)")
                    mediaFact("Sources", value: "\(model.sourceSummaries.count)")
                }

                if !model.statusBreakdown.isEmpty {
                    TagFlowLayout(spacing: Spacing.xs) {
                        ForEach(model.statusBreakdown) { status in
                            Label("\(status.displayName) \(status.count)", systemImage: "circle.fill")
                                .font(CiderFont.captionSemibold)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.hairline)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CiderColors.surfaceInput)
                                )
                        }
                    }
                }

                if !model.sourceSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Top sources")
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)

                        ForEach(model.sourceSummaries.prefix(4)) { source in
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "link")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                    .frame(width: Spacing.lg)

                                Text(source.host)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer(minLength: 0)

                                Text("\(source.count)")
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                        }
                    }
                } else {
                    mediaEmptyState(
                        title: "No sources summarized yet",
                        message: "As MediaItems and media bookmarks arrive, this panel will show whether Media is structured or still source-only."
                    )
                }
            }
        }
    }

    private var recommendedActionsPanel: some View {
        HomeOverviewPanel(title: "Next Best Actions") {
            if model.recommendedActions.isEmpty {
                mediaEmptyState(
                    title: "Media Space is calm",
                    message: "No review queue or obvious empty shelves need attention right now."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(model.recommendedActions) { action in
                        Button {
                            selectSection(action.section)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Image(systemName: action.systemImage)
                                    .font(CiderFont.bodySemibold)
                                    .foregroundColor(CiderColors.controlAccent)

                                Text(action.title)
                                    .font(CiderFont.labelSemibold)
                                    .foregroundColor(CiderColors.primary)
                                    .lineLimit(2)

                                Text(action.message)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                                    .lineLimit(2)

                                Text(action.actionLabel)
                                    .font(CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.controlAccent)
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
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
    }

    private var featuredShelfPanel: some View {
        HomeOverviewPanel(title: "Start From Your Saves") {
            if model.featuredItems.isEmpty {
                mediaEmptyState(
                    title: "No media saves found yet",
                    message: "Save a Steam page, movie trailer, Letterboxd item, Goodreads page, or media review and this Space will start building visual shelves from real Cider items."
                )
            } else {
                posterShelf(items: model.featuredItems)
            }
        }
    }

    private var tasteProfilePanel: some View {
        HomeOverviewPanel(title: "Taste Profile Foundation") {
            let signals = model.tasteSignals()

            if signals.isEmpty {
                mediaEmptyState(
                    title: "No taste notes found yet",
                    message: "Notes with favorites, liked games, movies, shows, books, or Hermes recommendation context will appear here as reviewable taste signals."
                )
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(signals.prefix(6)) { signal in
                        Button {
                            onOpenNote(signal.note)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: signal.section.systemImage)
                                    .font(CiderFont.bodyMedium)
                                    .foregroundColor(CiderColors.controlAccent)
                                    .frame(width: Spacing.xl)

                                VStack(alignment: .leading, spacing: Spacing.hairline) {
                                    Text(signal.note.title)
                                        .font(CiderFont.labelSemibold)
                                        .foregroundColor(CiderColors.primary)
                                        .lineLimit(1)

                                    Text("\(signal.reason) · \(signal.note.relativePath)")
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 0)
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

                Text("These are signals, not auto-imported media items. The next pass can let Hermes review them and propose items or recommendations.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionDetail(for section: MediaSpaceSectionKind) -> some View {
        let summary = model.summary(for: section)

        return VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
            HomeOverviewPanel(title: section.displayName) {
                if section == .tasteProfile {
                    if summary.tasteSignals.isEmpty {
                        mediaEmptyState(title: "No taste signals yet", message: section.subtitle)
                    } else {
                        tasteSignalGrid(summary.tasteSignals)
                    }
                } else if section == .inbox {
                    if summary.items.isEmpty {
                        mediaEmptyState(
                            title: "Nothing needs sorting",
                            message: "Conservative classification is doing its job. Ambiguous media-ish saves will appear here for review instead of being imported as the wrong thing."
                        )
                    } else {
                        needsSortingReviewList(summary.items)
                    }
                } else if summary.items.isEmpty {
                    mediaEmptyState(
                        title: "No \(section.displayName.lowercased()) yet",
                        message: "Capture or route matching saves into Media and they will appear here."
                    )
                } else {
                    posterShelf(items: summary.items, isLarge: true)
                }
            }

            if section != .tasteProfile && section != .inbox {
                HomeOverviewPanel(title: "Why These Are Here") {
                    ForEach(summary.items.prefix(6)) { item in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)

                            Text("\(item.title): \(item.reason)")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func mediaItemDetailPanel(_ item: MediaSpaceItem) -> some View {
        HomeOverviewPanel(
            title: item.detailMode == .structuredMediaItem ? "MediaItem Overview" : "Source Bookmark",
            headerAccessory: AnyView(
                Button {
                    selectedItem = nil
                } label: {
                    Label("Close", systemImage: "xmark")
                        .font(CiderFont.captionSemibold)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.tertiary)
            )
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    BookmarkThumbnailView(bookmark: item.bookmark, mode: .grid)
                        .frame(width: 84)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Label(item.section.displayName, systemImage: item.section.systemImage)
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.controlAccent)

                        Text(item.title)
                            .font(CiderFont.headingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.metadataSummary)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.reason)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                mediaItemMetaGrid(item)

                if let mediaItem = item.mediaItem {
                    mediaItemSourceList(mediaItem)
                    mediaItemExternalIDList(mediaItem)
                }

                Button {
                    onOpenBookmark(item.bookmark)
                } label: {
                    Label(
                        item.detailMode == .structuredMediaItem ? "Open Source" : "Open Bookmark",
                        systemImage: "arrow.up.right.square"
                    )
                    .font(CiderFont.captionSemibold)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.controlAccent)
            }
        }
    }

    private func mediaItemMetaGrid(_ item: MediaSpaceItem) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: Spacing.xs)], spacing: Spacing.xs) {
            mediaFact("Mode", value: item.detailMode == .structuredMediaItem ? "Structured" : "Source")
            mediaFact("Sources", value: "\(item.sourceCount)")
            mediaFact("Source host", value: item.sourceSubtitle)
            if let confidence = item.confidencePercent {
                mediaFact("Confidence", value: "\(confidence)%")
            }
            if let status = item.mediaItem?.status, status != .unknown {
                mediaFact("Status", value: status.rawValue.capitalized)
            }
        }
    }

    private func mediaFact(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(label.uppercased())
                .font(CiderFont.microBold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(0.8)

            Text(value)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    @ViewBuilder
    private func mediaItemSourceList(_ mediaItem: MediaItem) -> some View {
        let sources = mediaItem.sourceURLs + mediaItem.sourceRelativePaths
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Sources")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)

                ForEach(Array(sources.prefix(4).enumerated()), id: \.offset) { _, source in
                    Label(source, systemImage: source.hasPrefix("http") ? "link" : "doc")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaItemExternalIDList(_ mediaItem: MediaItem) -> some View {
        if !mediaItem.externalIDs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Stable IDs")
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(CiderColors.primary)

                TagFlowLayout(spacing: Spacing.xs) {
                    ForEach(mediaItem.externalIDs.keys.sorted(), id: \.self) { key in
                        if let value = mediaItem.externalIDs[key] {
                            Text("\(key): \(value)")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.hairline)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(CiderColors.surfaceInput)
                                )
                        }
                    }
                }
            }
        }
    }

    private func needsSortingReviewList(_ items: [MediaSpaceItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(items) { item in
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Image(systemName: item.section.systemImage)
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: Spacing.xl)

                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(item.title)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)

                        Text("\(item.sourceSubtitle) · \(item.reason)")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Button {
                        onOpenBookmark(item.bookmark)
                    } label: {
                        Label("Open Source", systemImage: "arrow.up.right.square")
                            .font(CiderFont.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CiderColors.controlAccent)
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
            }
        }
    }

    private func posterShelf(items: [MediaSpaceItem], isLarge: Bool = false) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: isLarge ? 150 : 132), spacing: Spacing.sm)],
            spacing: Spacing.md
        ) {
            ForEach(items) { item in
                MediaPosterCardView(item: item, isLarge: isLarge) {
                    openMediaItem(item)
                }
            }
        }
    }

    private func tasteSignalGrid(_ signals: [MediaTasteSignal]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm)], spacing: Spacing.sm) {
            ForEach(signals) { signal in
                Button {
                    onOpenNote(signal.note)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Image(systemName: signal.section.systemImage)
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.controlAccent)

                        Text(signal.note.title)
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(2)

                        Text(signal.reason)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mediaMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(value)
                .font(CiderFont.labelSemibold)
                .foregroundColor(CiderColors.primary)
            Text(label.uppercased())
                .font(CiderFont.microBold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(0.9)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }

    private func mediaEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            Text(message)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func selectSection(_ section: MediaSpaceSectionKind?) {
        selectedSection = section
        selectedItem = nil
    }

    private func openMediaItem(_ item: MediaSpaceItem) {
        if item.detailMode == .structuredMediaItem {
            selectedItem = item
        } else {
            onOpenBookmark(item.bookmark)
        }
    }
}

private struct MediaSpaceDashboardInputSignature: Equatable {
    let bookmarkCount: Int
    let bookmarkFingerprint: Int
    let mediaItemCount: Int
    let mediaItemFingerprint: Int
    let noteCount: Int
    let noteFingerprint: Int

    init(bookmarks: [Bookmark], mediaItems: [MediaItem], notes: [Note]) {
        bookmarkCount = bookmarks.count
        bookmarkFingerprint = bookmarks.reduce(into: Hasher()) { hasher, bookmark in
            hasher.combine(bookmark.id)
            hasher.combine(bookmark.updatedAt.timeIntervalSince1970)
        }
        .finalize()
        mediaItemCount = mediaItems.count
        mediaItemFingerprint = mediaItems.reduce(into: Hasher()) { hasher, item in
            hasher.combine(item.id)
            hasher.combine(item.updatedAt.timeIntervalSince1970)
        }
        .finalize()
        noteCount = notes.count
        noteFingerprint = notes.reduce(into: Hasher()) { hasher, note in
            hasher.combine(note.id)
            hasher.combine(note.modifiedAt.timeIntervalSince1970)
        }
        .finalize()
    }
}

private struct MediaPosterCardView: View {
    let item: MediaSpaceItem
    let isLarge: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                BookmarkThumbnailView(bookmark: item.bookmark, mode: .grid)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, CiderColors.overlayBadge],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: isLarge ? 76 : 62)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: Spacing.hairline) {
                                Text(item.title)
                                    .font(isLarge ? CiderFont.labelSemibold : CiderFont.captionSemibold)
                                    .foregroundColor(CiderColors.textOnColor)
                                    .lineLimit(2)

                                Text(item.sourceSubtitle)
                                    .font(CiderFont.micro)
                                    .foregroundColor(CiderColors.textOnColor.opacity(0.75))
                                    .lineLimit(1)
                            }
                            .padding(Spacing.xs)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                Label(item.section.displayName, systemImage: item.section.systemImage)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    if item.detailMode == .structuredMediaItem {
                        Label("MediaItem", systemImage: "checkmark.seal")
                            .font(CiderFont.microBold)
                            .foregroundColor(CiderColors.controlAccent)
                    }

                    if let confidence = item.confidencePercent {
                        Text("\(confidence)%")
                            .font(CiderFont.microBold)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(item.section.displayName)")
    }
}
