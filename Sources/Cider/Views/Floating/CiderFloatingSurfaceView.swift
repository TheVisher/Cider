import SwiftUI

struct CiderFloatingSurfaceView: View {
    let surface: CiderFloatableSurface
    var onDock: CiderFloatingDockAction?

    var body: some View {
        if surface.isLibraryItemSurface {
            CiderFloatingItemView(surface: surface, onDock: onDock)
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(surface.defaultTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    onDock?()
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .buttonStyle(.plain)
                .help("Dock back to Cider")
            }

            Divider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(surface.defaultTitle)
                    .font(.title3.weight(.semibold))

                Text(surface.fallbackDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(minWidth: 320, minHeight: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var iconName: String {
        switch surface {
        case .note:
            "note.text"
        case .bookmark, .bookmarkMetadata:
            "bookmark"
        case .contact:
            "person.crop.circle"
        case .dateCard:
            "calendar"
        case .todo:
            "checklist"
        case .clipboard:
            "clipboard"
        case .aiAssistant:
            "sparkles"
        case .dropZone:
            "tray.and.arrow.down"
        }
    }
}

private extension CiderFloatableSurface {
    var isLibraryItemSurface: Bool {
        switch self {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo:
            true
        case .clipboard, .aiAssistant, .dropZone:
            false
        }
    }
}
