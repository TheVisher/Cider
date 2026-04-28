import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CiderDropZoneView: View {
    @ObservedObject var context: CiderDropZoneContext
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            dropTarget
            recentDrops
        }
        .padding(Spacing.lg)
        .frame(width: 340, alignment: .topLeading)
        .frame(minHeight: 260, alignment: .topLeading)
        .background(.regularMaterial)
        .onDrop(
            of: CiderDropZoneDropDelegate.typeIdentifiers,
            delegate: CiderDropZoneDropDelegate(
                isTargeted: $isTargeted,
                context: context
            )
        )
        .onChange(of: isTargeted) { newValue in
            context.setTargeted(newValue)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 28, height: 28)
                .background(CiderColors.accentSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(context.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                Text(context.subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dropTarget: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: isTargeted ? "plus.circle.fill" : "plus.circle")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(isTargeted ? CiderColors.controlAccent : CiderColors.secondary)

            Text(context.status.message)
                .font(CiderFont.captionSemibold)
                .foregroundColor(statusColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("URLs become bookmarks. Files copy to Inbox. Everything else stays here for now.")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isTargeted ? CiderColors.dropTargetFill : CiderColors.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(
                    isTargeted ? CiderColors.dropTargetBorderStrong : CiderColors.borderSubtle,
                    style: StrokeStyle(lineWidth: CiderBorder.innerStrokeWidth, dash: [6, 5])
                )
        )
    }

    private var recentDrops: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if context.droppedItems.isEmpty {
                Text("No drops yet.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(context.droppedItems.prefix(4)) { item in
                        CiderDropZoneRecentRow(item: item)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch context.status {
        case .success:
            return CiderColors.success
        case .fallback:
            return CiderColors.warning
        case .failure:
            return CiderColors.destructive
        case .targeted, .processing:
            return CiderColors.controlAccent
        case .idle:
            return CiderColors.secondary
        }
    }
}

private struct CiderDropZoneRecentRow: View {
    let item: CiderDropZoneContext.DroppedItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(item.didPersist ? CiderColors.success : CiderColors.warning)
                .frame(width: 22, height: 22)
                .background(CiderColors.surfaceInput, in: RoundedRectangle(cornerRadius: Radius.xs))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text(item.detail)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(CiderColors.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var symbolName: String {
        switch item.kind {
        case .bookmark:
            return "link"
        case .file:
            return "doc"
        case .image:
            return "photo"
        case .text:
            return "text.alignleft"
        }
    }
}

private struct CiderDropZoneDropDelegate: DropDelegate {
    static let typeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.image.identifier,
        UTType.tiff.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier
    ]

    @Binding var isTargeted: Bool
    let context: CiderDropZoneContext

    func validateDrop(info: DropInfo) -> Bool {
        !providers(info).isEmpty
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
        let providers = providers(info)
        guard !providers.isEmpty else { return false }
        loadFirstSupportedItem(from: providers)
        return true
    }

    private func providers(_ info: DropInfo) -> [NSItemProvider] {
        info.itemProviders(for: Self.typeIdentifiers)
    }

    private func loadFirstSupportedItem(from providers: [NSItemProvider]) {
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                Task { @MainActor in
                    context.saveDroppedURL(url)
                }
            }
            return
        }

        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage,
                      let data = image.tiffRepresentation else { return }
                Task { @MainActor in
                    context.saveDroppedImageData(data, preferredFileExtension: "tiff")
                }
            }
            return
        }

        for provider in providers {
            if loadData(from: provider, typeIdentifier: UTType.fileURL.identifier, as: .url) { return }
            if loadData(from: provider, typeIdentifier: UTType.url.identifier, as: .url) { return }
            if loadData(from: provider, typeIdentifier: UTType.png.identifier, as: .image("png")) { return }
            if loadData(from: provider, typeIdentifier: UTType.jpeg.identifier, as: .image("jpg")) { return }
            if loadData(from: provider, typeIdentifier: UTType.tiff.identifier, as: .image("tiff")) { return }
            if loadData(from: provider, typeIdentifier: UTType.plainText.identifier, as: .text) { return }
            if loadData(from: provider, typeIdentifier: UTType.text.identifier, as: .text) { return }
        }

        Task { @MainActor in
            context.status = .failure("Drop type is not supported yet.")
        }
    }

    private enum DataRoute {
        case url
        case text
        case image(String)
    }

    private func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String,
        as route: DataRoute
    ) -> Bool {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                switch route {
                case .url:
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        context.saveDroppedURL(url)
                    } else if let rawValue = decodedString(from: data),
                              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        context.saveDroppedURL(url)
                    } else {
                        context.status = .failure("Dropped URL could not be read.")
                    }
                case .text:
                    if let text = decodedString(from: data) {
                        context.saveDroppedText(text)
                    } else {
                        context.status = .failure("Dropped text could not be read.")
                    }
                case .image(let preferredExtension):
                    context.saveDroppedImageData(data, preferredFileExtension: preferredExtension)
                }
            }
        }
        return true
    }

    private func decodedString(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }
}
