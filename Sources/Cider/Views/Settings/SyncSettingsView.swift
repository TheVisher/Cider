import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if authService.isLoggedIn {
                SettingsSection(title: "Sync Status") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            if syncService.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing...")
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.tertiary)
                            } else if let error = syncService.lastError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(CiderColors.warning)
                                    .font(CiderFont.label)
                                Text(error)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.warning)
                            } else if let lastSync = syncService.lastSyncedAt {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(CiderColors.success)
                                    .font(CiderFont.label)
                                Text("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                                    .font(CiderFont.body)
                                    .foregroundColor(CiderColors.tertiary)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(CiderColors.tertiary)
                                    .font(CiderFont.label)
                                Text("Sync is active")
                                    .font(CiderFont.body)
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

                        Text("Bookmarks, notes, and folders sync automatically across all your devices.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)

                        Button("Force Full Sync") {
                            syncService.forceReconcile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(syncService.isSyncing)
                    }
                }
            } else {
                SettingsSection(title: "Cider Web Sync") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Sign in to your Cider account to sync bookmarks, notes, and folders across all your devices.")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)

                        Text("Go to the Account section in the sidebar to sign in or create an account.")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
