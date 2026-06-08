import SwiftUI

// Load-URL row: paste a YouTube / YouTube Music URL and send it to the Beast.
extension BeastMenuView {
    var loadURLSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Paste a YouTube or YouTube Music URL", text: $urlDraft)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit(submitURL)
            Button(action: submitURL) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSendCommands || urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Play URL")
            .help("Play URL")
        }
    }

    func submitURL() {
        let next = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return }
        urlDraft = ""
        Task { await model.loadURL(next) }
    }
}
