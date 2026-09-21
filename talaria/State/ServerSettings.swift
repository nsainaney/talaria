import Foundation
import Observation

/// Where the Hermes dashboard lives and how to sign in. URL and username in UserDefaults,
/// password in the Keychain.
@Observable @MainActor
final class ServerSettings {
    private static let urlKey = "hermes.dashboardURL"
    private static let userKey = "hermes.username"
    private static let passwordKey = "hermes.password"

    var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: Self.urlKey) } }
    var username: String { didSet { UserDefaults.standard.set(username, forKey: Self.userKey) } }
    var password: String { didSet { Keychain.set(password, for: Self.passwordKey) } }

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? "http://127.0.0.1:9119"
        username = UserDefaults.standard.string(forKey: Self.userKey) ?? ""
        password = Keychain.get(Self.passwordKey) ?? ""
    }

    var isConfigured: Bool { url != nil && !username.isEmpty && !password.isEmpty }

    var url: URL? {
        var raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let u = URL(string: raw), u.host != nil else { return nil }
        return u
    }

    var auth: GatewayAuth? {
        guard let url, !username.isEmpty, !password.isEmpty else { return nil }
        return GatewayAuth(baseURL: url, username: username, password: password)
    }

    /// Sign out: forget the password (and username) so nothing signs in silently again.
    func clearCredentials() {
        password = ""
        username = ""
    }
}
