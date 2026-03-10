import AppKit
import SwiftTerm
import SwiftUI

// MARK: - SwiftUI Wrapper

struct CiderTerminalView: View {
    @StateObject private var viewModel = TerminalViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.sm) {
                Image(systemName: "terminal")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)

                Text(viewModel.title.isEmpty ? "Terminal" : viewModel.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel.restart()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Restart shell")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider()

            // Terminal
            TerminalNSViewWrapper(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var title: String = "Terminal"
    @Published private(set) var isRunning = false

    var terminalView: LocalProcessTerminalView?

    private let vaultPath: String = {
        StoragePaths.cachedVaultDirectoryURL.path
    }()

    func start() {
        guard let terminalView, !isRunning else { return }
        isRunning = true

        // Determine user's default shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build environment with PATH from user's shell
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

    func markStopped() {
        isRunning = false
    }

    func restart() {
        terminalView?.process?.terminate()
        isRunning = false
        // Small delay to let process cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }
}

// MARK: - NSView Wrapper

private struct TerminalNSViewWrapper: NSViewRepresentable {
    let viewModel: TerminalViewModel

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.processDelegate = context.coordinator
        tv.autoresizingMask = [.width, .height]

        // Style: dark terminal with monospace font
        tv.nativeBackgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        tv.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
        let fontSize: CGFloat = 13
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Store reference and start
        DispatchQueue.main.async {
            viewModel.terminalView = tv
            viewModel.start()
        }

        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let viewModel: TerminalViewModel

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — no action needed
        }

        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor [weak viewModel] in
                viewModel?.title = title
            }
        }

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could track current directory if needed
        }

        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor [weak viewModel] in
                viewModel?.markStopped()
            }
        }
    }
}
