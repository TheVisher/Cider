import AppKit
import SwiftUI

struct NativeMarkdownEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: NotesViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NativeMarkdownTextView()
        // Apply initial content before arming the delegate. Setting `string` after
        // assigning NSTextView.delegate can synchronously call textDidChange during
        // SwiftUI view creation, which publishes view-model changes from inside a
        // render/update pass when switching from rich mode to source mode.
        textView.string = viewModel.editingContent
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        textView.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.42, green: 0.71, blue: 0.93, alpha: 0.30)
        ]
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 28, height: 18)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.viewModel = viewModel

        if textView.string != viewModel.editingContent, !context.coordinator.isApplyingTextChange {
            context.coordinator.isApplyingTextChange = true
            let selectedRanges = textView.selectedRanges
            textView.string = viewModel.editingContent
            textView.selectedRanges = selectedRanges.compactMap { value in
                let range = value.rangeValue
                guard range.location <= textView.string.utf16.count else { return nil }
                let clampedLength = min(range.length, textView.string.utf16.count - range.location)
                return NSValue(range: NSRange(location: range.location, length: clampedLength))
            }
            context.coordinator.isApplyingTextChange = false
        }
        context.coordinator.applyFindSelectionIfNeeded(in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var viewModel: NotesViewModel
        weak var textView: NSTextView?
        var isApplyingTextChange = false
        private var lastAppliedFindQuery: String?

        init(viewModel: NotesViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingTextChange,
                  let textView = notification.object as? NSTextView else { return }
            viewModel.sourceContentChanged(textView.string)
        }

        @MainActor
        func applyFindSelectionIfNeeded(in textView: NSTextView) {
            let query = viewModel.findQuery
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard viewModel.isFindBarVisible, !query.isEmpty else {
                lastAppliedFindQuery = nil
                return
            }

            let nsText = textView.string as NSString
            let range = nsText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
            guard range.location != NSNotFound else {
                lastAppliedFindQuery = nil
                DispatchQueue.main.async { [weak viewModel] in
                    guard viewModel?.findQuery == query else { return }
                    viewModel?.findMatchCount = 0
                    viewModel?.findMatchIndex = 0
                }
                return
            }

            if lastAppliedFindQuery != query || textView.selectedRange() != range {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.window?.makeFirstResponder(textView)
                lastAppliedFindQuery = query
            }

            DispatchQueue.main.async { [weak viewModel] in
                guard viewModel?.findQuery == query else { return }
                viewModel?.findMatchCount = 1
                viewModel?.findMatchIndex = 1
            }
        }
    }
}

private final class NativeMarkdownTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
}
