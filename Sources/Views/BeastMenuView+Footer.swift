import AppKit
import SwiftUI

// Footer bar: live status detail text and a Quit button (mirrors Cmd+Q).
extension BeastMenuView {
    var footerSection: some View {
        HStack(spacing: 8) {
            Text(model.statusDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption.weight(.medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Quit Beast Remote")
            .help("Quit Beast Remote Menu Bar (⌘Q)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
    }
}
