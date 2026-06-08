import SwiftUI

// Secondary controls: shuffle and like pill buttons.
extension BeastMenuView {
    var secondaryControls: some View {
        HStack(spacing: 8) {
            pillButton("shuffle", label: "Shuffle") {
                Task { await model.command("shuffle") }
            }
            pillButton("heart", label: "Like") {
                Task { await model.command("toggleLike") }
            }
        }
        .disabled(!model.canSendCommands)
    }

    func pillButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemName)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
