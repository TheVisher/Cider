import SwiftUI

struct SyncSettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if authService.isLoggedIn {
                loggedInView
            } else {
                loginView
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Logged In

    private var loggedInView: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Account") {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(CiderColors.controlAccent)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(authService.accountEmail)
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(CiderColors.primary)

                        Text("Signed in")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    Spacer()

                    Button("Sign Out") {
                        authService.signOut()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection(title: "Sync") {
                syncStatusView
            }
        }
    }

    private var syncStatusView: some View {
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
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(CiderColors.tertiary)
                        .font(.system(size: 12))
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
        }
    }

    // MARK: - Login / Sign Up

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var loginView: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: isSignUp ? "Create Account" : "Sign In") {
                VStack(spacing: Spacing.sm) {
                    Text(isSignUp
                        ? "Create a Cider account to sync your bookmarks, notes, and folders across all your devices."
                        : "Sign in to sync your bookmarks, notes, and folders across all your devices.")
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: Spacing.xs) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Email")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .font(CiderFont.body)
                                .frame(maxWidth: 320)
                                .textContentType(.emailAddress)
                                .onSubmit(submit)
                        }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Password")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.secondary)
                            SecureField("••••••••", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .font(CiderFont.body)
                                .frame(maxWidth: 320)
                                .onSubmit(submit)
                        }

                        if isSignUp {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Confirm Password")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.secondary)
                                SecureField("••••••••", text: $confirmPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(CiderFont.body)
                                    .frame(maxWidth: 320)
                                    .onSubmit(submit)
                            }
                        }
                    }

                    if let error = authService.errorMessage {
                        Text(error)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: Spacing.sm) {
                        Button(action: submit) {
                            if authService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(authService.isLoading || email.isEmpty || password.isEmpty)

                        Spacer()

                        Button(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up") {
                            isSignUp.toggle()
                            authService.errorMessage = nil
                            confirmPassword = ""
                        }
                        .buttonStyle(.plain)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                    }
                }
            }
        }
    }

    private func submit() {
        if isSignUp {
            guard password == confirmPassword else {
                authService.errorMessage = "Passwords don't match"
                return
            }
        }

        Task {
            if isSignUp {
                await authService.signUp(email: email, password: password)
            } else {
                await authService.login(email: email, password: password)
            }
            if authService.isLoggedIn {
                email = ""
                password = ""
                confirmPassword = ""
            }
        }
    }
}
