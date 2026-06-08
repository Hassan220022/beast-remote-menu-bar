import SwiftUI

// Volume row: mute toggle, a 0...100 slider that commits on release, and a
// live numeric readout.
extension BeastMenuView {
    func volumeSection(for media: BeastMediaSnapshot) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.command(media.muted == true ? "unmute" : "mute") }
            } label: {
                Image(systemName: media.muted == true ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(media.muted == true ? Color.accentColor : .secondary)
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSendCommands)
            .accessibilityLabel(media.muted == true ? "Unmute" : "Mute")
            .help(media.muted == true ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { volumeDraft },
                    set: { volumeDraft = $0 }
                ),
                in: 0...100,
                onEditingChanged: { editing in
                    isAdjustingVolume = editing
                    if !editing {
                        Task { await model.setVolume(String(Int(volumeDraft.rounded()))) }
                    }
                }
            )
            .controlSize(.small)
            .tint(.accentColor)
            .disabled(!model.canSendCommands)
            .accessibilityLabel("Volume")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text("\(Int(volumeDraft.rounded()))")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }
}
