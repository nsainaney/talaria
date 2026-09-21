import Foundation
import Observation

/// Where the Hermes gateway lives. URL in UserDefaults, API key in the Keychain.
@Observable @MainActor
final class ServerSettings {
    private static let urlKey = "hermes.serverURL"
    private static let apiKeyKey = "hermes.apiKey"

    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.urlKey) }
    }
    var apiKey: String {
        didSet { Keychain.set(apiKey, for: Self.apiKeyKey) }
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? "http://127.0.0.1:8642"
        apiKey = Keychain.get(Self.apiKeyKey) ?? ""
    }

    var isConfigured: Bool { url != nil && !apiKey.isEmpty }

    var url: URL? {
        var raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let u = URL(string: raw), u.host != nil else { return nil }
        return u
    }

    var client: HermesClient? {
        guard let url, !apiKey.isEmpty else { return nil }
        return HermesClient(baseURL: url, apiKey: apiKey)
    }
}
