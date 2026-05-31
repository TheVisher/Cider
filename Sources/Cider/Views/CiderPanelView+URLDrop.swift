import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension CiderPanelView {
    static let urlDropTypeIdentifiers = [
        UTType.url.identifier,
        UTType.fileURL.identifier,
        BookmarkDragPayload.typeIdentifier,
        NoteDragPayload.typeIdentifier,
        MultiDragPayload.typeIdentifier
    ]

    var urlDropOverlay: some View {
        ZStack {
            CiderColors.backdrop

            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(CiderColors.accentSubtle)
                        .frame(width: 54, height: 54)

                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(CiderColors.controlAccent)
                }

                VStack(spacing: Spacing.xs) {
                    Text("Drop URL to Save Bookmark")
                        .font(CiderFont.headingSemibold)
                        .foregroundColor(CiderColors.primary)

                    Text(urlDropDestinationLabel)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(CiderColors.dropTargetBorder, lineWidth: CiderBorder.innerStrokeWidth)
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous)
                .stroke(CiderColors.dropTargetBorderStrong, lineWidth: CiderBorder.innerStrokeWidth)
                .padding(Spacing.sm)
        )
        .allowsHitTesting(false)
    }

    var urlDropDestinationLabel: String {
        guard let selectedFolderID,
              let folder = bookmarksViewModel.folders.first(where: { $0.id == selectedFolderID }) else {
            return "Saves to Inbox"
        }

        return "Saves to \(folder.name)"
    }

    @MainActor
    func saveDroppedURL(_ rawValue: String, folderID: UUID?) {
        let receipt: CaptureReceipt
        if let result = try? CiderBookmarkCaptureAdapter()
            .addURLBookmark(
                urlString: rawValue,
                folderID: folderID,
                sourceContext: CaptureSourceContext(
                    surface: "url_drop",
                    originalText: rawValue
                )
            ) {
            receipt = CaptureReceipt(result: result.captureResult)
        } else {
            receipt = .failed("Dropped content is not a URL")
        }
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "message": receipt.toastMessage(success: "Saved dropped URL"),
                "isSuccess": receipt.isSuccess
            ]
        )
    }
}

struct CiderPanelURLDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let targetFolderID: UUID?
    let onSaveDroppedURL: @MainActor (String, UUID?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        acceptsURLDrop(info.itemProviders(for: CiderPanelView.urlDropTypeIdentifiers))
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            isTargeted = false
            return nil
        }
        isTargeted = true
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: CiderPanelView.urlDropTypeIdentifiers)
        guard acceptsURLDrop(providers) else { return false }
        return loadDroppedURL(from: providers)
    }

    private func acceptsURLDrop(_ providers: [NSItemProvider]) -> Bool {
        !CiderInternalDragState.isActive
            && !providers.contains(where: isInternalCiderProvider)
            && providers.contains(where: isURLLikeProvider)
    }

    private func isInternalCiderProvider(_ provider: NSItemProvider) -> Bool {
        let identifiers = provider.registeredTypeIdentifiers
        let internalIdentifiers = [
            BookmarkDragPayload.typeIdentifier,
            NoteDragPayload.typeIdentifier,
            MultiDragPayload.typeIdentifier,
            UTType.fileURL.identifier
        ]
        return internalIdentifiers.contains { identifiers.contains($0) }
            || identifiers.contains(where: { $0.hasPrefix("com.cider.") })
    }

    private func isURLLikeProvider(_ provider: NSItemProvider) -> Bool {
        provider.canLoadObject(ofClass: NSURL.self)
            || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    }

    private func loadDroppedURL(from providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL else { return }
                Task { @MainActor in
                    onSaveDroppedURL(url.absoluteString, targetFolderID)
                }
            }
            return true
        }

        for typeIdentifier in CiderPanelView.urlDropTypeIdentifiers {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    guard let data else { return }

                    let rawValue: String?
                    if typeIdentifier == UTType.url.identifier,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        rawValue = url.absoluteString
                    } else {
                        rawValue = String(data: data, encoding: .utf8)
                            ?? String(data: data, encoding: .utf16)
                    }

                    guard let rawValue else { return }
                    Task { @MainActor in
                        onSaveDroppedURL(rawValue, targetFolderID)
                    }
                }
                return true
            }
        }

        return false
    }
}
