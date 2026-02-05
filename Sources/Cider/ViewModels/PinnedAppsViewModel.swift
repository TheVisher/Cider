import AppKit
import Combine

@MainActor
final class PinnedAppsViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var runningBundleIdentifiers: Set<String> = []
    @Published var runningApps: [AppInfo] = []  // Running apps that aren't pinned

    private let storageKey = "PinnedApps"
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        refreshRunning()
        observeRunningApps()
    }

    func isRunning(_ app: AppInfo) -> Bool {
        guard !app.bundleIdentifier.isEmpty else { return false }
        return runningBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func remove(_ app: AppInfo) {
        apps.removeAll { $0.id == app.id }
        save()
        // Refresh running apps list so the app appears in Running if still running
        refreshRunning()
    }

    func move(app: AppInfo, to target: AppInfo) {
        guard let fromIndex = apps.firstIndex(of: app),
              let toIndex = apps.firstIndex(of: target),
              fromIndex != toIndex else { return }
        let item = apps.remove(at: fromIndex)
        apps.insert(item, at: toIndex)
        save()
    }

    func importDockApps() {
        let path = ("~/Library/Preferences/com.apple.dock.plist" as NSString).expandingTildeInPath
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let persistentApps = dict["persistent-apps"] as? [[String: Any]] else {
            return
        }

        let imported = persistentApps.compactMap { entry -> AppInfo? in
            guard let tileData = entry["tile-data"] as? [String: Any] else { return nil }
            if let fileData = tileData["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String {
                let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
                return appInfo(from: url)
            }
            if let fileLabel = tileData["file-label"] as? String {
                let appURL = URL(fileURLWithPath: "/Applications/\(fileLabel).app")
                return appInfo(from: appURL)
            }
            return nil
        }

        let unique = Array(Set(imported)).sorted { $0.name.lowercased() < $1.name.lowercased() }
        if !unique.isEmpty {
            apps = unique
            save()
        }
    }

    func addApp(from url: URL) {
        guard let info = appInfo(from: url) else { return }
        if apps.contains(where: { $0.bundleIdentifier == info.bundleIdentifier || $0.path == info.path }) {
            return
        }
        apps.append(info)
        apps.sort { $0.name.lowercased() < $1.name.lowercased() }
        save()
        // Refresh running apps list so the app moves from Running to Pinned immediately
        refreshRunning()
    }

    private func appInfo(from url: URL) -> AppInfo? {
        let path = url.path
        guard path.hasSuffix(".app") else { return nil }
        guard let bundle = Bundle(path: path) else { return nil }
        let bundleId = bundle.bundleIdentifier ?? ""
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(name: name, bundleIdentifier: bundleId, path: path)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([AppInfo].self, from: data) {
            apps = stored
            print("[PinnedAppsViewModel] Loaded \(apps.count) apps: \(apps.map { $0.name })")
        } else {
            print("[PinnedAppsViewModel] No saved apps, importing from dock")
            importDockApps()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func refreshRunning() {
        let running = NSWorkspace.shared.runningApplications
        runningBundleIdentifiers = Set(running.compactMap { $0.bundleIdentifier })

        // Build list of running apps that aren't pinned
        let pinnedBundleIDs = Set(apps.map { $0.bundleIdentifier })
        let ownBundleID = Bundle.main.bundleIdentifier

        runningApps = running.compactMap { app -> AppInfo? in
            // Only regular apps (not background processes)
            guard app.activationPolicy == .regular else { return nil }
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
            // Skip our own app
            guard bundleID != ownBundleID else { return nil }
            // Skip if already pinned
            guard !pinnedBundleIDs.contains(bundleID) else { return nil }
            // Get app info
            guard let bundleURL = app.bundleURL else { return nil }
            let name = app.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
            return AppInfo(name: name, bundleIdentifier: bundleID, path: bundleURL.path)
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func observeRunningApps() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: center.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .sink { [weak self] _ in
                self?.refreshRunning()
            }
            .store(in: &cancellables)

        // Observe minimized state changes to update the UI immediately
        NotificationCenter.default.publisher(for: .ciderMinimizedStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
