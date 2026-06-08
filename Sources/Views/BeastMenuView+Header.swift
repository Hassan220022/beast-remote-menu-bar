import SwiftUI

// Header bar: connection status glyph, app title + live connection text, an
// online/offline pill, and a manual refresh button.
extension BeastMenuView {
    var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.connected ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                Image(systemName: model.connected ? "music.note" : "bolt.horizontal.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.connected ? .green : .orange)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Beast Remote")
                    .font(.headline)
                Text(model.connectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            statusPill

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .accessibilityLabel("Refresh")
            .disabled(!model.isConfigured)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.connected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(model.connected ? "Online" : "Offline")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(model.connected ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel(model.connected ? "Online" : "Offline")
    }
}
