import AppKit
import UniformTypeIdentifiers

final class CiderStatusDropTarget: NSView {
    nonisolated static let acceptedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.image.identifier,
        UTType.tiff.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier
    ]

    private let onActivate: () -> Void
    private var didActivateForCurrentDrag = false

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        super.init(frame: .zero)
        registerForDraggedTypes(Self.acceptedPasteboardTypes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    static var acceptedPasteboardTypes: [NSPasteboard.PasteboardType] {
        acceptedTypeIdentifiers.map { NSPasteboard.PasteboardType($0) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        activateIfNeeded()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        activateIfNeeded()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        didActivateForCurrentDrag = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        didActivateForCurrentDrag = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        activateIfNeeded()
        return false
    }

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    private func activateIfNeeded() {
        guard !didActivateForCurrentDrag else { return }
        didActivateForCurrentDrag = true
        onActivate()
    }
}
