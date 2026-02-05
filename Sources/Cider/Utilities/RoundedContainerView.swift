import AppKit

final class RoundedContainerView: NSView {
    var cornerRadius: CGFloat = CiderDesign.cornerRadius

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
    }

    override func layout() {
        super.layout()
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
    }
}
