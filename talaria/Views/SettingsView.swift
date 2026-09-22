import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var busy = false
    @AppStorage(Speaker.voiceKey) private var voiceId = ""

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section("Hermes dashboard") {
                    TextField("http://host:9119", text: $settings.serverURL)
                        .keyboardType(.URL).textContentType(.URL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Username", text: $settings.username)
                        .textContentType(.username).autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("Password", text: $settings.password)
                        .textContentType(.password)
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack { Text("Sign in"); Spacer(); if busy { ProgressView() } }
                    }
                    .disabled(!settings.isConfigured || busy)
                    if let status { Text(status).font(.footnote) }
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(connectionLabel).foregroundStyle(.secondary)
                    }
                    if let v = model.serverVersion {
                        HStack { Text("Hermes version"); Spacer(); Text(v).foregroundStyle(.secondary) }
                    }
                } footer: {
                    Text("The dashboard must run with a username/password provider (HERMES_DASHBOARD_BASIC_AUTH_*) and be reachable from this device. The password is kept in the Keychain; the dashboard session renews itself silently.")
                }
                Section {
                    Toggle("Voice mode", isOn: $settings.voiceEnabled)
                    if settings.voiceEnabled {
                        Toggle("Hermes voice (server)", isOn: $settings.serverVoice)
                        Toggle("Low reasoning while talking", isOn: $settings.voiceFastModel)
                        if settings.voiceFastModel {
                            TextField("Model alias (optional, e.g. fast)", text: $settings.voiceModelAlias)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                        Picker(settings.serverVoice ? "Fallback voice" : "Voice", selection: $voiceId) {
                            Text("Automatic (best installed)").tag("")
                            ForEach(Speaker.availableVoices(), id: \.identifier) { v in
                                Text("\(v.name) · \(qualityLabel(v.quality))").tag(v.identifier)
                            }
                        }
                    }
                } footer: {
                    Text("Listening happens on this phone. With Hermes voice on, replies are synthesized by the server's TTS provider (Pocket TTS on prometheus) and the phone voice is used only if that fails. Talk over a reply to stop it; permission requests take a spoken allow, always or deny. For a better phone voice, download a Premium or Enhanced one in iOS Settings › Accessibility › Spoken Content › Voices. Low reasoning: while voice mode is on the session answers with less thinking time and switches back afterwards. Naming a model alias also swaps the model for the whole turn, tools included, so leave it empty unless you want the faster, weaker model doing the work.")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await model.signOut(); status = "Signed out"; }
                    }
                    .disabled(settings.password.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    private var connectionLabel: String {
        switch model.gateway.state {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting(let n): return "Reconnecting (\(n))…"
        case .failed(let why): return "Failed: \(why)"
        }
    }

    private func signIn() async {
        guard let auth = model.settings.auth else { return }
        busy = true
        defer { busy = false }
        do {
            let s = try await auth.status()
            if s.authRequired && !s.providers.contains("basic") {
                status = "Dashboard has no username/password provider (has: \(s.providers.joined(separator: ", ")))."
                return
            }
            try await auth.login()
            status = "Signed in" + (s.version.map { " · Hermes \($0)" } ?? "")
            await model.connect()
        } catch let e as URLError {
            status = "\(e.localizedDescription) (URLError \(e.code.rawValue))" + (e.failingURL.map { " \($0.absoluteString)" } ?? "")
        } catch {
            status = error.localizedDescription
        }
    }
}
