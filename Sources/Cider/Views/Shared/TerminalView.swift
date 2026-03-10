import AppKit
import SwiftTerm
import SwiftUI

// MARK: - AI Model Definition

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let command: String

    static let builtIn: [AIModelOption] = [
        AIModelOption(id: "shell", name: "Shell", icon: "terminal", command: ""),
        AIModelOption(id: "claude", name: "Claude", icon: "bubble.left.and.text.bubble.right", command: "claude"),
        AIModelOption(id: "chatgpt", name: "ChatGPT", icon: "bubble.left.and.text.bubble.right", command: "chatgpt"),
        AIModelOption(id: "codex", name: "Codex", icon: "chevron.left.forwardslash.chevron.right", command: "codex"),
    ]
}

// MARK: - Header View (SwiftUI — title bar + model selector only)

struct AIChatHeaderView: View {
    let viewModel: TerminalViewModel
    @Binding var selectedModel: AIModelOption
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
                .padding(.horizontal, Spacing.md + Spacing.xxs)
            modelSelector
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                NotificationCenter.default.post(name: .dismissAIChatPanel, object: nil)
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.microBold)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")

            Image(systemName: "sparkles")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)

            Text("AI Chat")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)

            Spacer()

            Button {
                viewModel.restart()
                if selectedModel.id != "shell" {
                    launchModel(selectedModel)
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restart session")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AIChatPanelDesign.titleBarHeight)
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(AIModelOption.builtIn) { model in
                    modelPill(model)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(height: AIChatPanelDesign.modelSelectorHeight)
        .padding(.vertical, Spacing.xs)
    }

    private func modelPill(_ model: AIModelOption) -> some View {
        let isSelected = selectedModel.id == model.id

        return Button {
            guard selectedModel.id != model.id else { return }
            withAnimation(reduceMotion ? .none : .snappy) {
                selectedModel = model
            }
            viewModel.restart()
            if model.id != "shell" {
                launchModel(model)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: model.icon)
                    .font(CiderFont.captionMedium)
                Text(model.name)
                    .font(CiderFont.captionMedium)
            }
            .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSubtle : CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? CiderColors.accentBorder : CiderColors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(model.id == "shell" ? "Plain shell" : "Launch \(model.name)")
    }

    // MARK: - Model Launch

    private func launchModel(_ model: AIModelOption) {
        guard !model.command.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            viewModel.sendCommand(model.command)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var title: String = ""
    @Published private(set) var isRunning = false

    var terminalView: LocalProcessTerminalView?

    private let vaultPath: String = {
        StoragePaths.cachedVaultDirectoryURL.path
    }()

    func start() {
        guard let terminalView, !isRunning else { return }
        isRunning = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            env.removeAll(where: { $0.hasPrefix("PATH=") })
            env.append("PATH=\(path)")
        }
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env.removeAll(where: { $0.hasPrefix("HOME=") })
            env.append("HOME=\(home)")
        }

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: vaultPath
        )
    }

    func sendCommand(_ command: String) {
        guard let terminalView, isRunning else { return }
        let data = Array((command + "\n").utf8)
        terminalView.send(data)
    }

    func markStopped() {
        isRunning = false
    }

    func restart() {
        terminalView?.process?.terminate()
        isRunning = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }
}

// MARK: - Terminal Process Delegate

@MainActor
final class TerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let viewModel: TerminalViewModel

    init(viewModel: TerminalViewModel) {
        self.viewModel = viewModel
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak viewModel] in
            viewModel?.title = title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak viewModel] in
            viewModel?.markStopped()
        }
    }
}

// MARK: - Composite Content View (pure AppKit)

/// The panel's content view: a SwiftUI header on top, raw AppKit terminal on the bottom.
/// The terminal is NOT inside SwiftUI, so it receives all key events normally.
final class AIChatContentView: NSView {
    let viewModel = TerminalViewModel()
    private var processDelegate: TerminalProcessDelegate?
    private var headerHostingView: NSHostingView<AnyView>?
    private(set) var terminalView: LocalProcessTerminalView?
    private var selectedModel = AIModelOption.builtIn[0]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        setupAcrylicBackground()
        setupHeader()
        setupTerminal()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupAcrylicBackground() {
        // Acrylic material — matches CiderPanel's AcrylicPanelBackground
        let vibrancy = NSVisualEffectView(frame: .zero)
        vibrancy.material = .underWindowBackground
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vibrancy)
        NSLayoutConstraint.activate([
            vibrancy.topAnchor.constraint(equalTo: topAnchor),
            vibrancy.leadingAnchor.constraint(equalTo: leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: trailingAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Dark tint overlay (same as CiderColors.acrylicTint: black @ 0.45)
        let tint = NSView(frame: .zero)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupHeader() {
        // Use @State-like binding by re-creating the hosting view on model change.
        // For the initial setup, create with the default model.
        let headerView = AIChatHeaderView(
            viewModel: viewModel,
            selectedModel: .constant(selectedModel)
        )
        let hosting = NSHostingView(rootView: AnyView(headerView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = []
        // Transparent so the acrylic background shows through
        hosting.layer?.backgroundColor = .clear
        addSubview(hosting)
        headerHostingView = hosting

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.heightAnchor.constraint(equalToConstant: AIChatPanelDesign.headerHeight),
        ])
    }

    private func setupTerminal() {
        let delegate = TerminalProcessDelegate(viewModel: viewModel)
        self.processDelegate = delegate

        let tv = LocalProcessTerminalView(frame: .zero)
        tv.processDelegate = delegate
        tv.translatesAutoresizingMaskIntoConstraints = false

        // Clear background so the acrylic material shows through
        tv.nativeBackgroundColor = .clear
        tv.nativeForegroundColor = NSColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1.0)
        tv.selectedTextBackgroundColor = NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1.0)
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        addSubview(tv)
        terminalView = tv
        viewModel.terminalView = tv

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: topAnchor, constant: AIChatPanelDesign.headerHeight),
            tv.leadingAnchor.constraint(equalTo: leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Start the shell after the view is in the hierarchy
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.start()
        }
    }

    override func layout() {
        super.layout()
        // Apply rounded-corner mask to the whole content view
        let radius = AIChatPanelDesign.cornerRadius
        let mask = CAShapeLayer()
        mask.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        layer?.mask = mask
    }
}

// MARK: - Legacy full-SwiftUI view (kept for reference, unused)
// The panel now uses AIChatContentView (pure AppKit) instead.
