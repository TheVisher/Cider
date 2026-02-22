import SwiftUI

struct BookmarkDetailsDraft: Equatable {
    let id: UUID
    let urlString: String
    let hostDisplay: String
    let createdAt: Date
    let updatedAt: Date
    var title: String
    var tagsText: String
    var notes: String

    init(bookmark: Bookmark) {
        id = bookmark.id
        urlString = bookmark.urlString
        hostDisplay = bookmark.hostDisplay
        createdAt = bookmark.createdAt
        updatedAt = bookmark.updatedAt
        title = bookmark.title
        tagsText = bookmark.tags.joined(separator: ", ")
        notes = bookmark.notes
    }
}

struct BookmarkDetailsSheet: View {
    @Binding var draft: BookmarkDetailsDraft
    var bookmark: Bookmark?
    var errorMessage: String?
    let onOpenURL: () -> Void
    let onCopyURL: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            canvas
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: BookmarksDesign.detailsSheetMinHeight, maxHeight: BookmarksDesign.detailsSheetMaxHeight)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                CiderColors.acrylicOverlayTint
                CiderColors.surfaceSubtle
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg - CiderBorder.innerStrokeInset, style: .continuous)
                .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                .padding(CiderBorder.innerStrokeInset)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                BookmarksTrafficLightButton(
                    color: .systemRed,
                    symbol: "xmark",
                    help: "Close details",
                    action: onCancel
                )
                BookmarksTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: "Close details",
                    action: onCancel
                )
                BookmarksTrafficLightButton(
                    color: .systemGreen,
                    symbol: "safari",
                    help: "Open bookmark",
                    action: onOpenURL
                )
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { proxy in
            let sidebarWidth = resolvedSidebarWidth(for: proxy.size.width)
            ZStack {
                RoundedRectangle(
                    cornerRadius: BookmarksDesign.detailsCanvasCornerRadius,
                    style: .continuous
                )
                .fill(CiderColors.surfaceHighlight)

                leftContent
                    .padding(.leading, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                    .padding(.trailing, sidebarWidth + Spacing.xl)

                HStack {
                    Spacer(minLength: 0)
                    sidebar(width: sidebarWidth)
                        .padding(.vertical, BookmarksDesign.detailsCanvasInset)
                        .padding(.trailing, BookmarksDesign.detailsCanvasInset)
                }
            }
        }
    }

    @ViewBuilder
    private var leftContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BookmarkDetailsHeroPreview(bookmark: bookmark, draft: draft)
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: BookmarksDesign.detailsHeroMinHeight,
                    maxHeight: BookmarksDesign.detailsHeroMaxHeight
                )
                .shadow(
                    color: CiderColors.shadowMedium,
                    radius: BookmarksDesign.detailsFloatingLiftBlur,
                    x: 0,
                    y: BookmarksDesign.detailsFloatingLiftYOffset
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(draft.title)
                    .font(CiderFont.heroTitle(scale: textScale))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(3)

                HStack(spacing: Spacing.xs) {
                    Text(draft.hostDisplay)
                        .font(CiderFont.labelMedium(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                    Text("\u{2022}")
                        .font(CiderFont.captionSemibold(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                    Text(draft.updatedAt.formatted(.relative(presentation: .named)))
                        .font(CiderFont.label(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Metadata")
                .font(CiderFont.bodySemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("URL")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(draft.urlString)
                        .font(CiderFont.label(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: BookmarksDesign.detailsSheetURLMinHeight)
                .padding(.horizontal, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
            }

            HStack(spacing: Spacing.sm) {
                Button(action: onOpenURL) {
                    Label("Open", systemImage: "link")
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .frame(minHeight: BookmarksDesign.buttonTapTarget)
                        .padding(.horizontal, Spacing.sm)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

                Button(action: onCopyURL) {
                    Label("Copy URL", systemImage: "doc.on.doc")
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .frame(minHeight: BookmarksDesign.buttonTapTarget)
                        .padding(.horizontal, Spacing.sm)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )

                Button(action: openOriginalImage) {
                    Label("Open Image", systemImage: "photo")
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .frame(minHeight: BookmarksDesign.buttonTapTarget)
                        .padding(.horizontal, Spacing.sm)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .disabled(!hasOpenableImageSource)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Title")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                TextField("Bookmark title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Tags")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                TextField("Comma-separated tags", text: $draft.tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Notes")
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                TextEditor(text: $draft.notes)
                    .font(CiderFont.label(scale: textScale))
                    .frame(
                        minHeight: BookmarksDesign.detailsSheetNotesMinHeight,
                        idealHeight: BookmarksDesign.detailsSheetNotesHeight,
                        maxHeight: BookmarksDesign.detailsSheetNotesHeight
                    )
                    .padding(Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }

            BookmarkDetailsPlaceholderSection(
                title: "Folders",
                subtitle: "Folder assignment coming soon",
                icon: "folder"
            )
            BookmarkDetailsPlaceholderSection(
                title: "Backlinks",
                subtitle: "Linked bookmarks coming soon",
                icon: "link.badge.plus"
            )
            BookmarkDetailsPlaceholderSection(
                title: "Attachments",
                subtitle: "Files and references coming soon",
                icon: "paperclip"
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(CiderFont.bodyMedium(scale: textScale))
                    .foregroundColor(CiderColors.destructive)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Updated \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                Text("Created \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
            }

            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)

                Button("Cancel", action: onCancel)
                    .buttonStyle(CiderSecondaryButtonStyle())

                Button("Save", action: onSave)
                    .buttonStyle(CiderAccentButtonStyle())
            }
        }
        .padding(Spacing.md)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .shadow(
            color: CiderColors.shadowMedium,
            radius: BookmarksDesign.detailsFloatingLiftBlur,
            x: 0,
            y: BookmarksDesign.detailsFloatingLiftYOffset
        )
    }

    private func resolvedSidebarWidth(for containerWidth: CGFloat) -> CGFloat {
        let maxCandidate = containerWidth * BookmarksDesign.detailsSidebarWidthRatio
        return min(
            max(maxCandidate, BookmarksDesign.detailsSidebarMinWidth),
            BookmarksDesign.detailsSidebarMaxWidth
        )
    }

    private var hasOpenableImageSource: Bool {
        if let originalFileURL = bookmark?.originalImageFileURL {
            return FileManager.default.fileExists(atPath: originalFileURL.path)
        }
        if let remote = bookmark?.thumbnailRemoteURLString {
            return URL(string: remote) != nil
        }
        return false
    }

    private func openOriginalImage() {
        if let originalFileURL = bookmark?.originalImageFileURL,
           FileManager.default.fileExists(atPath: originalFileURL.path) {
            NSWorkspace.shared.open(originalFileURL)
            return
        }

        if let remote = bookmark?.thumbnailRemoteURLString,
           let remoteURL = URL(string: remote) {
            NSWorkspace.shared.open(remoteURL)
        }
    }
}

// MARK: - Hero Preview

struct BookmarkDetailsHeroPreview: View {
    let bookmark: Bookmark?
    let draft: BookmarkDetailsDraft

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?

    private var palette: (Color, Color) {
        let seed = bookmark?.urlString ?? draft.urlString
        let pairs: [(NSColor, NSColor)] = [
            (.systemBlue, .systemTeal),
            (.systemIndigo, .systemBlue),
            (.systemOrange, .systemYellow),
            (.systemPink, .systemRed),
            (.systemMint, .systemGreen),
            (.systemCyan, .systemBlue),
        ]
        let index = abs(seed.hashValue) % pairs.count
        return (Color(pairs[index].0), Color(pairs[index].1))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(stageBackground)
            .overlay {
                heroContent
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderStrong, lineWidth: CiderBorder.innerStrokeWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .task(id: thumbnailFingerprint) {
                await loadThumbnailAsync()
            }
    }

    @ViewBuilder
    private var heroContent: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.md)
                .shadow(color: CiderColors.shadowMedium, radius: 8, x: 0, y: 3)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Spacer(minLength: 0)
                Text(String(draft.hostDisplay.prefix(1)).uppercased())
                    .font(.system(size: BookmarksDesign.detailsHeroFallbackLetterSize * textScale, weight: .black))
                    .foregroundColor(CiderColors.textOnColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
        }
    }

    private var stageBackground: some ShapeStyle {
        if thumbnailImage != nil {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        CiderColors.stageGradientStart,
                        CiderColors.stageGradientEnd,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [palette.0.opacity(CiderColors.gradientTint), palette.1.opacity(CiderColors.gradientTint)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var thumbnailFingerprint: String {
        let path = bookmark?.thumbnailFileURL?.path ?? ""
        let ts = String(bookmark?.metadataUpdatedAt?.timeIntervalSince1970 ?? -1)
        let remote = bookmark?.thumbnailRemoteURLString ?? ""
        return "\(path)|\(ts)|\(remote)"
    }

    private func loadThumbnailAsync() async {
        guard let fileURL = bookmark?.thumbnailFileURL else {
            thumbnailImage = nil
            return
        }

        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value

        guard !Task.isCancelled else { return }
        thumbnailImage = image
    }
}

// MARK: - Placeholder Section

struct BookmarkDetailsPlaceholderSection: View {
    let title: String
    let subtitle: String
    let icon: String

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Label(title, systemImage: icon)
                .font(CiderFont.captionSemibold(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            Text(subtitle)
                .font(CiderFont.body(scale: textScale))
                .foregroundColor(CiderColors.quaternary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Traffic Light Button

struct BookmarksTrafficLightButton: View {
    let color: NSColor
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: NotesDesign.trafficLightDiameter, height: NotesDesign.trafficLightDiameter)
                .overlay {
                    if isHovered {
                        Image(systemName: symbol)
                            .font(.system(size: NotesDesign.trafficLightSymbolSize * CiderFont.scale, weight: .semibold))
                            .foregroundColor(CiderColors.trafficLightSymbol)
                    }
                }
                .frame(width: NotesDesign.trafficLightTapTarget, height: NotesDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered)
        .help(help)
    }
}
