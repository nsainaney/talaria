import SwiftUI
import MarkdownUI

struct ChatRow: View {
    let item: ChatItem
    @State private var expanded = false

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(item.images.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(item.fileNames, id: \.self) { name in
                        Label(name, systemImage: "doc.text").font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    if !item.text.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            if item.isSteer {
                                Label("Steer", systemImage: "arrow.turn.down.right").font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(verbatim: item.text).textSelection(.enabled)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(item.isSteer ? 0.10 : 0.18), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(.horizontal)

        case .assistant:
            Markdown(item.text)
                .markdownTextStyle(\.code) {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.9))
                    BackgroundColor(Color(.secondarySystemBackground))
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    ScrollView(.horizontal, showsIndicators: false) {
                        configuration.label
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(0.85))
                            }
                            .padding(12)
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .markdownMargin(top: 4, bottom: 8)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

        case .reasoning:
            DisclosureGroup(isExpanded: $expanded) {
                Text(item.text).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(.top, 4)
            } label: {
                Label(item.isStreaming ? "Thinking…" : "Reasoning", systemImage: "brain")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

        case .tool:
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if !item.text.isEmpty {
                        Text(item.text).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if let r = item.toolResult, !r.isEmpty {
                        Divider()
                        Text(r).font(.caption.monospaced()).foregroundStyle(item.toolError ? .red : .secondary).textSelection(.enabled)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    if item.isStreaming { ProgressView().controlSize(.mini) }
                    else { Image(systemName: item.toolError ? "xmark.circle" : "checkmark.circle").foregroundStyle(item.toolError ? .red : .green) }
                    Text(item.toolName ?? "tool").font(.footnote.monospaced())
                    if let d = item.toolDuration { Text(String(format: "%.1fs", d)).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

        case .commentary:
            Text(item.text).italic().foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)

        case .notice:
            Text(item.text).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center).padding(.horizontal)

        case .error:
            Label(item.text, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
        }
    }
}
