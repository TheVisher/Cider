import SwiftUI

struct CiderFloatingSurfaceView: View {
    let surface: CiderFloatableSurface
    var onDock: CiderFloatingDockAction?
    var onReanchor: CiderFloatingReanchorAction?

    var body: some View {
        if surface.isLibraryItemSurface {
            CiderFloatingItemView(
                surface: surface,
                onDock: onDock,
                onReanchor: onReanchor
            )
        } else if surface == .aiAssistant {
            AIAssistantPanelView(
                viewModel: AIAssistantViewModel.shared,
                onClose: onDock,
                onFloat: { reanchorSurface() },
                showsResizeOverlay: false,
                presentationStyle: .floatingSurface
            )
            .frame(minWidth: AIAssistantPanelDesign.minWidth, minHeight: AIAssistantPanelDesign.minHeight)
        } else if case .kanbanTestingGuide(let payload) = surface {
            KanbanTestingGuideFloatingView(
                payload: payload,
                onDock: onDock,
                onReanchor: onReanchor
            )
            .frame(minWidth: 360, minHeight: 420)
        } else if surface == .journalIntelligence {
            JournalIntelligencePanelView(onDock: onDock)
                .frame(minWidth: 640, minHeight: 560)
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
        case .vaultFile:
            "doc"
        case .clipboard:
            "clipboard"
        case .aiAssistant:
            "sparkles"
        case .dropZone:
            "tray.and.arrow.down"
        case .kanbanTestingGuide:
            "checkmark.seal"
        case .journalIntelligence:
            "brain.head.profile"
        }
    }

    @MainActor
    private func reanchorSurface() {
        if let onReanchor {
            onReanchor(surface)
        } else {
            NotificationCenter.default.post(
                name: .reanchorCiderSurface,
                object: surface,
                userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
            )
        }
    }
}

private extension CiderFloatableSurface {
    var isLibraryItemSurface: Bool {
        switch self {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo, .vaultFile:
            true
        case .clipboard, .aiAssistant, .dropZone, .journalIntelligence, .kanbanTestingGuide:
            false
        }
    }
}
