import SwiftUI

struct SyncSettingsView: View {
    @State private var config = CiderConfig.load()
    @State private var syncURL: String = ""
    @State private var syncToken: String = ""
    @State private var syncEnabled: Bool = false
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cider Web Sync")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)

            Text("Sync bookmarks with Cider Web so you can capture on your phone and see them here.")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)

            VStack(alignment: .leading, spacing: 12) {
                // Sync URL
                VStack(alignment: .leading, spacing: 4) {
                    Text("Convex Site URL")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                    TextField("https://your-app-123.convex.site", text: $syncURL)
                        .textFieldStyle(.roundedBorder)
                        .font(CiderFont.body)
                        .frame(maxWidth: 400)
                        .onChange(of: syncURL) { _, newValue in
                            config.syncURL = newValue
                            config.save()
                        }
                }

                // Sync Token
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Token")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                    SecureField("Paste your sync token from Cider Web", text: $syncToken)
                        .textFieldStyle(.roundedBorder)
                        .font(CiderFont.body)
                        .frame(maxWidth: 400)
                        .onChange(of: syncToken) { _, newValue in
                            config.syncToken = newValue
                            config.save()
                        }
                }

                // Enable toggle
                Toggle(isOn: $syncEnabled) {
                    Text("Enable sync")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                }
                .toggleStyle(.switch)
                .disabled(syncURL.isEmpty || syncToken.isEmpty)
                .onChange(of: syncEnabled) { _, newValue in
                    config.syncEnabled = newValue
                    config.save()
                    NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
                }

                // Status
                if syncEnabled {
                    HStack(spacing: 8) {
                        if syncService.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        } else if let error = syncService.lastError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text(error)
                                .font(CiderFont.caption)
                                .foregroundColor(.orange)
                        } else if let lastSync = syncService.lastSyncedAt {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }

                        Spacer()

                        Button("Sync Now") {
                            syncService.syncNow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(syncService.isSyncing)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .onAppear {
            let loaded = CiderConfig.load()
            syncURL = loaded.syncURL
            syncToken = loaded.syncToken
            syncEnabled = loaded.syncEnabled
        }
    }
}
