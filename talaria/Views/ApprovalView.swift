import SwiftUI

/// Popup for an `approval.request` event. The run is parked server-side until a choice is posted.
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
        let action = { Task { await model.chat.respond(to: request, choice: choice) } }
        if choice == "deny" {
            Button(action: { _ = action() }) { Label(label, systemImage: icon).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).tint(.red)
        } else {
            Button(action: { _ = action() }) { Label(label, systemImage: icon).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
    }
}
