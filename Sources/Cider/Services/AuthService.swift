import Foundation
import os

/// Handles authentication with the Cider backend.
/// On login/signup, receives a sync token and stores it in Keychain.
/// The existing SyncService uses this token for all sync operations.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    private static let logger = Logger(subsystem: "com.cider", category: "AuthService")
    private static let emailKey = "CiderAccountEmail"

    @Published var isLoggedIn: Bool = false
    @Published var accountEmail: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

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

        isLoading = true
        errorMessage = nil

        do {
            let result = try await callAuthEndpoint(
                path: "/api/auth/login",
                email: trimmedEmail,
                password: password
            )
            applyAuthResult(result, email: trimmedEmail)
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("Login failed: \(error)")
        }

        isLoading = false
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

        isLoading = true
        errorMessage = nil

        do {
            let result = try await callAuthEndpoint(
                path: "/api/auth/signup",
                email: trimmedEmail,
                password: password
            )
            applyAuthResult(result, email: trimmedEmail)
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("Sign up failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        SyncService.saveSyncToken("")
        UserDefaults.standard.removeObject(forKey: Self.emailKey)

        var config = CiderConfig.load()
        config.syncEnabled = false
        config.save()

        isLoggedIn = false
        accountEmail = ""
        errorMessage = nil

        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
        Self.logger.info("Signed out")
    }

    // MARK: - Private

    private struct AuthResponse: Decodable {
        let token: String?
        let email: String?
        let error: String?
    }

    private func callAuthEndpoint(path: String, email: String, password: String) async throws -> AuthResponse {
        let config = CiderConfig.load()
        let baseURL = config.syncURL.isEmpty
            ? "https://dashing-fennec-334.convex.site"
            : config.syncURL

        guard let url = URL(string: baseURL + path) else {
            throw AuthError.invalidURL
        }
        guard Self.isSecureAuthURL(url) else {
            throw AuthError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if os(macOS)
        let deviceName = Host.current().localizedName ?? "Mac"
        #else
        let deviceName = "iOS"
        #endif

        let body: [String: String] = [
            "email": email,
            "password": password,
            "deviceName": deviceName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

        if let error = decoded.error {
            throw AuthError.serverError(error)
        }

        guard httpResponse.statusCode == 200 else {
            throw AuthError.serverError(decoded.error ?? "Request failed with status \(httpResponse.statusCode)")
        }

        return decoded
    }

    private func applyAuthResult(_ result: AuthResponse, email: String) {
        guard let token = result.token else {
            errorMessage = "No token received"
            return
        }

        // Store credentials
        SyncService.saveSyncToken(token)
        UserDefaults.standard.set(email, forKey: Self.emailKey)

        // Enable sync
        var config = CiderConfig.load()
        if config.syncURL.isEmpty {
            config.syncURL = "https://dashing-fennec-334.convex.site"
        }
        config.syncEnabled = true
        config.save()

        isLoggedIn = true
        accountEmail = email
        errorMessage = nil

        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
        Self.logger.info("Logged in as \(email)")
    }

    enum AuthError: LocalizedError {
        case invalidURL
        case insecureURL
        case networkError
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .insecureURL: return "Sync login requires HTTPS"
            case .networkError: return "Network error — check your connection"
            case .serverError(let msg): return msg
            }
        }
    }

    private static func isSecureAuthURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        #if DEBUG
        if scheme == "http",
           let host = url.host?.lowercased(),
           ["localhost", "127.0.0.1", "::1"].contains(host) {
            return true
        }
        #endif
        return false
    }
}
