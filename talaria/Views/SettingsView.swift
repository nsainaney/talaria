import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var busy = false

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
                } footer: {
                    Text("Listening and speaking happen on this phone. Tap the microphone in the composer to talk to Hermes; talk over a reply to stop it. Permission requests are read aloud and take a spoken allow, always or deny.")
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
