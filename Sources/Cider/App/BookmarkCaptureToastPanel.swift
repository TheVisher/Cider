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

struct BookmarkCaptureToastView: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        ZStack {
            AcrylicPanelBackground(cornerRadius: BookmarksToastDesign.cornerRadius, shadowStyle: .compact)

            HStack(spacing: Spacing.sm) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSuccess ? Color(NSColor.systemGreen) : Color(NSColor.systemYellow))

                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.sm)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .frame(width: BookmarksToastDesign.width, height: BookmarksToastDesign.height)
        .padding(BookmarksToastDesign.shadowPadding)
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
            AcrylicPanelBackground(cornerRadius: BookmarksToastDesign.cornerRadius, shadowStyle: .compact)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CiderColors.controlAccent)

                    Text("Save copied URL?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CiderColors.primary)

                    Spacer(minLength: Spacing.sm)
                }

                Text(urlDisplay)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    Button(action: onDiscard) {
                        Text("Discard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CiderColors.secondary)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CiderColors.controlAccent)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: BookmarksDesign.buttonTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(CiderColors.controlAccent.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: Spacing.sm)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(Color.white.opacity(0.14))

                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.controlAccent.opacity(0.88))
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
