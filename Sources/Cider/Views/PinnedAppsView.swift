import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PinnedAppsView: View {
    @ObservedObject var viewModel: PinnedAppsViewModel
    let isCompact: Bool
    private let appLauncher = AppLauncher()

    @State private var draggingApp: AppInfo? = nil

    private var columns: [GridItem] {
        // Always use adaptive grid - panel is always full width
        return [GridItem(.adaptive(minimum: CiderDesign.iconSize), spacing: Spacing.sm)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Pinned Apps Header
            HStack {
                Text("Pinned Apps")
                    .font(.caption)
                    .foregroundColor(CiderColors.secondary)
                Spacer()
                Button("Add App") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [UTType.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        viewModel.addApp(from: url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(CiderColors.controlAccent)
                .accessibilityLabel("Add pinned app")
                .accessibilityHint("Opens file picker to select an application")
                Button("Import Dock") {
                    viewModel.importDockApps()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(CiderColors.controlAccent)
                .accessibilityLabel("Import apps from Dock")
            }

            // Pinned Apps Grid
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(Array(viewModel.apps.enumerated()), id: \.element.id) { index, app in
                    PinnedAppIconView(app: app,
                                      isRunning: viewModel.isRunning(app),
                                      isMinimized: WindowCache.shared.isManuallyMinimized(appPID(for: app)),
                                      launch: {
                                          NSLog("[PinnedApps] Button tapped for app at index \(index): \(app.name), path: \(app.path)")
                                          appLauncher.launchOrFocus(app)
                                      },
                                      remove: { viewModel.remove(app) },
                                      pin: nil,
                                      showInFinder: { appLauncher.showInFinder(app) },
                                      onDragStart: { draggingApp = app })
                    .onDrop(of: [.text], delegate: PinnedAppsDropDelegate(target: app,
                                                                         draggingApp: $draggingApp,
                                                                         viewModel: viewModel))
                }
            }
            .padding(.top, Spacing.xs)

            // Running Apps Section (apps that are running but not pinned)
            if !viewModel.runningApps.isEmpty {
                HStack {
                    Text("Running")
                        .font(.caption)
                        .foregroundColor(CiderColors.secondary)
                    Spacer()
                }
                .padding(.top, Spacing.sm)

                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(viewModel.runningApps) { app in
                        PinnedAppIconView(app: app,
                                          isRunning: true,
                                          isMinimized: WindowCache.shared.isManuallyMinimized(appPID(for: app)),
                                          launch: {
                                              NSLog("[RunningApps] Button tapped for: \(app.name)")
                                              appLauncher.launchOrFocus(app)
                                          },
                                          remove: nil,
                                          pin: { viewModel.addApp(from: URL(fileURLWithPath: app.path)) },
                                          showInFinder: { appLauncher.showInFinder(app) },
                                          onDragStart: {})
                    }
                }
            }
        }
        .padding(Spacing.sm)
    }

    private func appPID(for app: AppInfo) -> pid_t {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {
            return running.processIdentifier
        }
        return 0
    }
}

private struct PinnedAppIconView: View {
    let app: AppInfo
    let isRunning: Bool
    let isMinimized: Bool
    let launch: () -> Void
    let remove: (() -> Void)?  // nil for running apps (not pinned)
    let pin: (() -> Void)?     // nil for pinned apps
    let showInFinder: () -> Void
    let onDragStart: () -> Void

    var body: some View {
        Button {
            NSLog("[PinnedAppIconView] Button action for: \(app.name)")
            launch()
        } label: {
            ZStack(alignment: .bottom) {
                appIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: CiderDesign.iconSize, height: CiderDesign.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: CiderDesign.iconCornerRadius,
                                                style: .continuous))
                    .opacity(isMinimized ? 0.5 : 1.0)  // Dim if minimized
                if isRunning {
                    Circle()
                        .fill(isMinimized ? Color.orange : CiderColors.success)
                        .frame(width: CiderDesign.runningIndicatorSize, height: CiderDesign.runningIndicatorSize)
                        .offset(y: CiderDesign.runningIndicatorOffset)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.name)\(isRunning ? ", running" : "")")
        .accessibilityHint("Click to open, right-click for options")
        .contextMenu {
            if let remove = remove {
                Button("Remove from Cider") {
                    remove()
                }
            }
            if let pin = pin {
                Button("Pin to Cider") {
                    pin()
                }
            }
            Button("Show in Finder") {
                showInFinder()
            }
        }
    }

    private var appIcon: Image {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 64, height: 64)
        return Image(nsImage: icon)
    }
}

private struct PinnedAppsDropDelegate: DropDelegate {
    let target: AppInfo
    @Binding var draggingApp: AppInfo?
    let viewModel: PinnedAppsViewModel

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingApp, dragging != target else { return }
        viewModel.move(app: dragging, to: target)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingApp = nil
        return true
    }
}
