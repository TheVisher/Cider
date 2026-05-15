import SwiftUI

struct RecipeSpaceDashboardView: View {
    let space: CiderSpace
    let rootURL: URL
    let captureDashboard: CiderSpaceCaptureDashboard?
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onTogglePinned: () -> Void
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void

    @State private var selectedItem: RecipeCollectionItem?
    @State private var localRatings: [String: RecipeRating] = [:]

    private var currentModel: RecipeSpaceDashboardModel {
        var model = RecipeSpaceDashboardModel.make(bookmarks: bookmarks)
        if !localRatings.isEmpty {
            model = RecipeSpaceDashboardModel(items: model.items.map { item in
                guard let rating = localRatings[item.id] else { return item }
                var copy = item
                copy.rating = rating
                return copy
            })
        }
        return model
    }

    private var bookmarksByID: [UUID: Bookmark] {
        Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })
    }

    var body: some View {
        let model = currentModel

        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - (Spacing.md * 2)), HomeOverviewDesign.maxContentWidth)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HomeOverviewDesign.rowSpacing) {
                        heroPanel(model: model)
                        captureRoutingPanel
                        sourceAndTastePanel(model: model)

                        if let selectedItem {
                            detailPanel(selectedItem)
                                .id("recipe-detail")
                        }

                        collectionPanel(model: model, scrollProxy: scrollProxy)
                        reviewPanel(model: model, scrollProxy: scrollProxy)
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

    private func heroPanel(model: RecipeSpaceDashboardModel) -> some View {
        HomeOverviewPanel(
            title: "Recipes Space",
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
            HStack(alignment: .center, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.34), Color.yellow.opacity(0.18), CiderColors.surfaceInput],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Recipe Collection")
                        .font(CiderFont.displayBold)
                        .foregroundColor(CiderColors.primary)
                    Text("Saved dishes and social recipe ideas with original source backlinks, reviewable extraction, and taste signals.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.sm) {
                recipeMetric("\(model.totalRecipeItems)", label: "recipe saves")
                recipeMetric("\(model.needsReviewItems.count)", label: "need review")
                recipeMetric("\(model.likedItems.count)", label: "liked")
                recipeMetric("\(model.dislikedItems.count)", label: "disliked")
            }
        }
    }

    private func sourceAndTastePanel(model: RecipeSpaceDashboardModel) -> some View {
        HomeOverviewPanel(title: "Sources + Taste") {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Source backlinks")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .tracking(1.2)
                    if model.sourceSummaries.isEmpty {
                        Text("Recipe-ish bookmarks from Food/Recipes, TikTok, YouTube, and recipe sites will appear here.")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.secondary)
                    } else {
                        TagFlowLayout(spacing: Spacing.xs) {
                            ForEach(model.sourceSummaries) { summary in
                                Label("\(summary.platform.displayName) · \(summary.count)", systemImage: sourceIcon(summary.platform))
                                    .font(CiderFont.captionMedium)
                                    .foregroundColor(CiderColors.secondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Capsule().fill(CiderColors.surfaceInput))
                            }
                        }
                    }
                }

                Divider().background(CiderColors.separator)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Taste signals")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .tracking(1.2)
                    Text("Use quick like/dislike now. Per-person kid/family reactions are modeled for the next persistence pass.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func collectionPanel(model: RecipeSpaceDashboardModel, scrollProxy: ScrollViewProxy) -> some View {
        HomeOverviewPanel(title: "Collection") {
            if model.items.isEmpty {
                emptyState(title: "No recipe saves yet", message: "Save recipe links into Food/Recipes or capture TikTok/YouTube/social recipe links and they will show up as collection cards.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(model.items) { item in
                        RecipeCollectionCardView(
                            item: item,
                            rating: localRatings[item.id] ?? item.rating,
                            onSelect: { select(item, scrollProxy: scrollProxy) },
                            onRate: { rating in localRatings[item.id] = rating },
                            onOpenSource: { openSource(for: item) }
                        )
                    }
                }
            }
        }
    }

    private func reviewPanel(model: RecipeSpaceDashboardModel, scrollProxy: ScrollViewProxy) -> some View {
        HomeOverviewPanel(title: "Needs Review") {
            if model.needsReviewItems.isEmpty {
                emptyState(title: "Nothing waiting", message: "Parsed or manually cleaned recipe items will stay in the main collection.")
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(model.needsReviewItems.prefix(6)) { item in
                        Button {
                            select(item, scrollProxy: scrollProxy)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: sourceIcon(item.sourcePlatform))
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(CiderFont.bodySemibold)
                                        .foregroundColor(CiderColors.primary)
                                    Text("\(item.extractionStatus.displayName) · \(item.sourceBacklinkLabel)")
                                        .font(CiderFont.caption)
                                        .foregroundColor(CiderColors.tertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .padding(Spacing.sm)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(CiderColors.surfaceInput))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detailPanel(_ item: RecipeCollectionItem) -> some View {
        HomeOverviewPanel(title: "Recipe Source") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(CiderFont.headingSemibold)
                        .foregroundColor(CiderColors.primary)
                    Spacer()
                    Text(item.extractionStatus.displayName)
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }

                detailRow("Source", value: item.sourceBacklinkLabel)
                detailRow("URL", value: item.sourceURL)
                if let relativePath = item.sourceRelativePath {
                    detailRow("Bookmark", value: relativePath)
                }
                if !item.ingredients.isEmpty {
                    detailRow(item.extractionStatus == .parsed || item.metadataChips.contains("Recipe pulled") ? "Ingredients" : "Ingredient hints", value: item.ingredients.joined(separator: " · "))
                }
                if !item.instructions.isEmpty {
                    detailRow("Steps", value: item.instructions.prefix(3).joined(separator: " · "))
                }
                let rating = localRatings[item.id] ?? item.rating
                detailRow("Taste", value: rating?.displayName ?? "Not rated")

                HStack(spacing: Spacing.sm) {
                    Button("Open Source") { openSource(for: item) }
                    Button("Liked") { localRatings[item.id] = .liked }
                    Button("Disliked") { localRatings[item.id] = .disliked }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func recipeMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
            Text(label.uppercased())
                .font(CiderFont.microBold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.1)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(CiderColors.surfaceInput))
    }

    private func emptyState(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "fork.knife")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                Text(message)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(CiderColors.surfaceInput))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label.uppercased())
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .tracking(1.2)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func openSource(for item: RecipeCollectionItem) {
        if let id = item.sourceBookmarkID, let bookmark = bookmarksByID[id] {
            onOpenBookmark(bookmark)
        }
    }

    private func select(_ item: RecipeCollectionItem, scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.16)) {
            selectedItem = item
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                scrollProxy.scrollTo("recipe-detail", anchor: .top)
            }
        }
    }

    private func sourceIcon(_ platform: RecipeSourcePlatform) -> String {
        switch platform {
        case .tiktok: "music.note.tv"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .recipeSite: "doc.text.image"
        case .web: "link"
        }
    }
}

private struct RecipeCollectionCardView: View {
    let item: RecipeCollectionItem
    let rating: RecipeRating?
    let onSelect: () -> Void
    let onRate: (RecipeRating) -> Void
    let onOpenSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            recipeArt

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Label(item.sourceBacklinkLabel, systemImage: sourceIcon(item.sourcePlatform))
                        .font(CiderFont.microBold)
                        .foregroundColor(.orange)
                    Spacer(minLength: 0)
                    Text(item.extractionStatus.displayName.uppercased())
                        .font(CiderFont.microBold)
                        .foregroundColor(CiderColors.tertiary)
                }

                Text(item.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.ingredients.isEmpty {
                    Text(item.ingredients.prefix(4).joined(separator: " · "))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }

                if !item.instructions.isEmpty {
                    Label("\(item.instructions.count) steps pulled", systemImage: "list.number")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                } else {
                    Text("Source-backed recipe candidate")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: Spacing.xs) {
                    ratingButton(.liked, systemImage: "hand.thumbsup.fill")
                    ratingButton(.disliked, systemImage: "hand.thumbsdown.fill")
                    Spacer(minLength: 0)
                    Button(action: onOpenSource) {
                        Image(systemName: "arrow.up.right.square")
                            .font(CiderFont.captionSemibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CiderColors.tertiary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(CiderColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var recipeArt: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.30), Color.yellow.opacity(0.20), CiderColors.surfaceInput],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .center) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.orange.opacity(0.76))
                }

            if !item.metadataChips.isEmpty {
                TagFlowLayout(spacing: Spacing.xxs) {
                    ForEach(item.metadataChips.prefix(3), id: \.self) { chip in
                        Text(chip)
                            .font(CiderFont.microBold)
                            .foregroundColor(CiderColors.textOnColor)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Capsule().fill(Color.black.opacity(0.32)))
                    }
                }
                .padding(Spacing.xs)
            }
        }
        .frame(height: 124)
    }

    private func ratingButton(_ target: RecipeRating, systemImage: String) -> some View {
        Button { onRate(target) } label: {
            Image(systemName: systemImage)
                .font(CiderFont.captionSemibold)
                .foregroundColor(rating == target ? .orange : CiderColors.tertiary)
                .padding(Spacing.xs)
                .background(Circle().fill(rating == target ? Color.orange.opacity(0.16) : CiderColors.surfaceInput))
        }
        .buttonStyle(.plain)
    }

    private func sourceIcon(_ platform: RecipeSourcePlatform) -> String {
        switch platform {
        case .tiktok: "music.note.tv"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .recipeSite: "doc.text.image"
        case .web: "link"
        }
    }
}
