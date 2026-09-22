import Foundation
import Observation

/// Where the Hermes dashboard lives and how to sign in. URL and username in UserDefaults,
/// password in the Keychain.
@Observable @MainActor
final class ServerSettings {
    private static let urlKey = "hermes.dashboardURL"
    private static let userKey = "hermes.username"
    private static let passwordKey = "hermes.password"
    private static let voiceKey = "talaria.voiceEnabled"
    private static let serverVoiceKey = "talaria.serverVoice"
    private static let fastVoiceKey = "talaria.voiceFastModel"
    private static let voiceAliasKey = "talaria.voiceModelAlias"

    var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: Self.urlKey) } }
    var username: String { didSet { UserDefaults.standard.set(username, forKey: Self.userKey) } }
    var password: String { didSet { Keychain.set(password, for: Self.passwordKey) } }
    /// Shows the microphone button. Off hides every voice feature without touching anything else.
    var voiceEnabled: Bool { didSet { UserDefaults.standard.set(voiceEnabled, forKey: Self.voiceKey) } }
    /// Speak replies with the voice configured on the Hermes server (Pocket TTS) instead of the phone's.
    var serverVoice: Bool { didSet { UserDefaults.standard.set(serverVoice, forKey: Self.serverVoiceKey) } }
    /// While voice mode is on, run the session at low reasoning effort (the model stays unless an alias is named).
    var voiceFastModel: Bool { didSet { UserDefaults.standard.set(voiceFastModel, forKey: Self.fastVoiceKey) } }
    /// Optional model alias for spoken turns; empty keeps the session's model. Note the alias runs the
    /// whole agent loop (tools included), not just the chat.
    var voiceModelAlias: String { didSet { UserDefaults.standard.set(voiceModelAlias, forKey: Self.voiceAliasKey) } }

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? "http://127.0.0.1:9119"
        username = UserDefaults.standard.string(forKey: Self.userKey) ?? ""
        password = Keychain.get(Self.passwordKey) ?? ""
        voiceEnabled = UserDefaults.standard.object(forKey: Self.voiceKey) as? Bool ?? true
        serverVoice = UserDefaults.standard.object(forKey: Self.serverVoiceKey) as? Bool ?? true
        voiceFastModel = UserDefaults.standard.object(forKey: Self.fastVoiceKey) as? Bool ?? true
        voiceModelAlias = UserDefaults.standard.string(forKey: Self.voiceAliasKey) ?? ""
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
