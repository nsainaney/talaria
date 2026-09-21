import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section("Hermes server") {
                    TextField("http://127.0.0.1:8642", text: $settings.serverURL)
                        .keyboardType(.URL).textContentType(.URL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("API_SERVER_KEY", text: $settings.apiKey)
                }
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack { Text("Test connection"); Spacer(); if testing { ProgressView() } }
                    }
                    .disabled(!settings.isConfigured || testing)
                    if let status { Text(status).font(.footnote) }
                } footer: {
                    Text("Enable the API server in ~/.hermes/.env with API_SERVER_ENABLED=true and API_SERVER_KEY, then run `hermes gateway`.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func test() async {
        guard let client = model.settings.client else { return }
        testing = true
        defer { testing = false }
        do {
            let ok = try await client.health()
            // /health may be unauthenticated; also touch an authenticated route so a bad key shows up here.
            _ = try await client.listSessions(limit: 1)
            status = ok ? "Connected" : "Server responded but reported a non-ok status"
        } catch {
            status = error.localizedDescription
        }
    }
}
