import SwiftUI

/// Popup for an `approval` server request. The turn is parked until a choice is sent back.
struct ApprovalView: View {
    @Environment(AppModel.self) private var model
    let request: ApprovalRequest

    private static let labels: [String: (String, String)] = [
        "once": ("Allow once", "checkmark"),
        "session": ("Allow for session", "checkmark.circle"),
        "always": ("Always allow", "checkmark.seal"),
        "deny": ("Deny", "xmark"),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let t = request.toolName, !t.isEmpty {
                    Text(t).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !request.description.isEmpty {
                    Text(request.description)
                }
                if !request.command.isEmpty {
                    ScrollView(.horizontal) {
                        Text(request.command).font(.callout.monospaced()).textSelection(.enabled).padding(10)
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                ForEach(request.choices, id: \.self) { choice in
                    choiceButton(choice)
                }
            }
            .padding()
            .navigationTitle("Permission needed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func choiceButton(_ choice: String) -> some View {
        let (label, icon) = Self.labels[choice] ?? (choice.capitalized, "questionmark")
        if choice == "deny" {
            Button { model.chat.respond(to: request, choice: choice) } label: { Label(label, systemImage: icon).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).tint(.red)
        } else {
            Button { model.chat.respond(to: request, choice: choice) } label: { Label(label, systemImage: icon).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Popup for a `clarify` server request: one question, optional choices, free-text otherwise.
struct ClarifyView: View {
    @Environment(AppModel.self) private var model
    let request: ClarifyRequest
    @State private var answer = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(request.question)
                if request.choices.isEmpty {
                    TextField("Your answer", text: $answer, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                    Button("Send") { model.chat.respond(to: request, answer: answer) }
                        .buttonStyle(.borderedProminent)
                        .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    ForEach(request.choices, id: \.self) { c in
                        Button { model.chat.respond(to: request, answer: c) } label: { Text(c).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Hermes is asking")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
