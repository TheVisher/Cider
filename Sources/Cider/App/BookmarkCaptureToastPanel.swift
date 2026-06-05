import AppKit
import SwiftUI

final class BookmarkCaptureToastPanel: NSPanel {
    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: BookmarksToastDesign.panelWidth,
            height: BookmarksToastDesign.panelHeight
        )

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovable = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BookmarkClipboardReviewToastModel: ObservableObject {
    @Published var progress: CGFloat = 1
}

struct BookmarkCaptureToastContent: Equatable {
    enum Kind: Equatable {
        case simple
        case receipt
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let badges: [String]
    let iconSystemName: String
    let isSuccess: Bool
    let contentHeight: CGFloat
    let titleLineLimit: Int

    init(message: String, isSuccess: Bool) {
        self.kind = .simple
        self.title = message
        self.subtitle = nil
        self.badges = []
        self.iconSystemName = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        self.isSuccess = isSuccess
        self.contentHeight = BookmarksToastDesign.height
        self.titleLineLimit = 2
    }

    init(receipt: UICaptureReceipt, successMessage: String) {
        self.kind = .receipt
        self.title = receipt.item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? receipt.shortToastMessage(success: successMessage)
        self.subtitle = Self.subtitle(for: receipt)
        self.badges = Self.badges(for: receipt, successMessage: successMessage)
        self.iconSystemName = receipt.state == .partialSideEffects || receipt.state == .failed
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle.fill"
        self.isSuccess = receipt.state != .partialSideEffects && receipt.state != .failed
        self.contentHeight = BookmarksToastDesign.richHeight
        self.titleLineLimit = 2
    }

    private static func subtitle(for receipt: UICaptureReceipt) -> String? {
        let type = receipt.item.type?.capitalized
        let destination = receipt.item.folderName?.nilIfEmpty
            ?? receipt.item.relativePath?.split(separator: "/").dropLast().last.map(String.init)
            ?? receipt.item.relativePath?.nilIfEmpty

        switch (type, destination) {
        case let (type?, destination?):
            return "\(type) - \(destination)"
        case let (type?, nil):
            return type
        case let (nil, destination?):
            return destination
        case (nil, nil):
            return nil
        }
    }

    private static func badges(for receipt: UICaptureReceipt, successMessage: String) -> [String] {
        var badges: [String] = [receipt.shortToastMessage(success: successMessage)]

        if receipt.duplicate.isDuplicate {
            badges.append("Duplicate")
        }
        if receipt.routing.reviewNeeded || receipt.routing.reviewState == "needs_review" {
            badges.append("Review needed")
            badges.append(receipt.safeNextActionLabel)
        }
        if receipt.state == .partialSideEffects {
            badges.append("Needs repair")
        }
        if receipt.provenance.isIncomplete {
            badges.append("Provenance \(receipt.provenance.status)")
        }
        if receipt.indexing.isIncomplete {
            badges.append("Indexing \(receipt.indexing.status)")
        }
        if receipt.captureQuality?.needsEnrichment == true {
            badges.append("Needs enrichment")
        }
        if receipt.captureQuality?.degraded == true {
            badges.append("Quality warning")
        }

        return orderedUnique(badges)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct BookmarkCaptureToastView: View {
    let content: BookmarkCaptureToastContent

    init(message: String, isSuccess: Bool) {
        self.content = BookmarkCaptureToastContent(message: message, isSuccess: isSuccess)
    }

    init(content: BookmarkCaptureToastContent) {
        self.content = content
    }

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: BookmarksToastDesign.cornerRadius)

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: content.iconSystemName)
                    .font(CiderFont.labelSemibold)
                    .foregroundColor(content.isSuccess ? CiderColors.success : CiderColors.warning)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(content.title)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(content.titleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)
                    }

                    if !content.badges.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            ForEach(content.badges.prefix(3), id: \.self) { badge in
                                Text(badge)
                                    .font(CiderFont.captionMedium)
                                    .foregroundColor(CiderColors.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(CiderColors.surfaceInput)
                                    )
                            }
                        }
                    }
                }

                Spacer(minLength: Spacing.sm)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: BookmarksToastDesign.width, height: content.contentHeight)
        .padding(BookmarksToastDesign.shadowPadding)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct BookmarkClipboardReviewToastView: View {
    @ObservedObject var model: BookmarkClipboardReviewToastModel
    let urlDisplay: String
    let onHoverChanged: (Bool) -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: BookmarksToastDesign.cornerRadius)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link.badge.plus")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text("Save copied URL?")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)

                    Spacer(minLength: Spacing.sm)
                }

                Text(urlDisplay)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    Button(action: onDiscard) {
                        Text("Discard")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(CiderColors.secondary)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text("Save")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.controlAccent)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.selectedFill)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: Spacing.sm)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.borderSelected)

                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.accentSolid)
                            .frame(width: proxy.size.width * max(0, min(1, model.progress)))
                    }
                }
                .frame(height: BookmarksToastDesign.reviewProgressHeight)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: BookmarksToastDesign.width, height: BookmarksToastDesign.reviewHeight)
        .padding(BookmarksToastDesign.shadowPadding)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }
}

struct ImageClipboardReviewToastView: View {
    @ObservedObject var model: BookmarkClipboardReviewToastModel
    let onHoverChanged: (Bool) -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: BookmarksToastDesign.cornerRadius)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "photo.badge.plus")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.controlAccent)

                    Text("Save copied image?")
                        .font(CiderFont.labelSemibold)
                        .foregroundColor(CiderColors.primary)

                    Spacer(minLength: Spacing.sm)
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: onDiscard) {
                        Text("Discard")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(CiderColors.secondary)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text("Save")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.controlAccent)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.selectedFill)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: Spacing.sm)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.borderSelected)

                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.accentSolid)
                            .frame(width: proxy.size.width * max(0, min(1, model.progress)))
                    }
                }
                .frame(height: BookmarksToastDesign.reviewProgressHeight)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: BookmarksToastDesign.width, height: BookmarksToastDesign.reviewHeight)
        .padding(BookmarksToastDesign.shadowPadding)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }
}

final class BookmarkCaptureToastHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
