import Foundation
import os

/// Handles authentication with the Cider backend.
/// Remote account sync is currently unavailable while sync is rebuilt.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    private static let logger = Logger(subsystem: "com.cider", category: "AuthService")
    private static let emailKey = "CiderAccountEmail"

    @Published var isLoggedIn: Bool = false
    @Published var accountEmail: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    var isRemoteAccountSyncAvailable: Bool { false }

    private init() {
        // Check if we have a stored token + email
        let token = SyncService.loadSyncToken()
        let email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        if !token.isEmpty && !email.isEmpty {
            isLoggedIn = true
            accountEmail = email
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required"
            return
        }

        errorMessage = "Cider account sync is unavailable while the new sync backend is rebuilt."
        Self.logger.info("Login ignored because remote account sync is unavailable")
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required"
            return
        }

        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            return
        }

        errorMessage = "Cider account sync is unavailable while the new sync backend is rebuilt."
        Self.logger.info("Sign up ignored because remote account sync is unavailable")
    }

    // MARK: - Sign Out

    func signOut() {
        SyncService.saveSyncToken("")
        UserDefaults.standard.removeObject(forKey: Self.emailKey)

        disableLegacySyncConfig()

        isLoggedIn = false
        accountEmail = ""
        errorMessage = nil

        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
        Self.logger.info("Signed out")
    }

    // MARK: - Private

    private func disableLegacySyncConfig() {
        var config = CiderConfig.load()
        config.syncEnabled = false
        config.syncURL = ""
        config.save()
    }
}
