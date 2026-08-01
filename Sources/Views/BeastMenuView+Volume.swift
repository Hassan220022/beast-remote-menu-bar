import SwiftUI

// Two volume rows: YouTube Music player volume (companion) and Beast system
// output volume (wpctl on the Linux host).
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
            .accessibilityLabel("YouTube Music volume")

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

    var systemVolumeSection: some View {
        let sysMuted = model.systemMuted == true
        return HStack(spacing: 10) {
            Button {
                Task { await model.toggleSystemMute() }
            } label: {
                Image(systemName: sysMuted ? "macwindow" : "macwindow.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sysMuted ? Color.accentColor : .secondary)
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSendCommands)
            .accessibilityLabel(sysMuted ? "Unmute Beast" : "Mute Beast")
            .help(sysMuted ? "Unmute Beast system" : "Mute Beast system")

            Slider(
                value: Binding(
                    get: { systemVolumeDraft },
                    set: { systemVolumeDraft = $0 }
                ),
                in: 0...100,
                onEditingChanged: { editing in
                    isAdjustingSystemVolume = editing
                    if !editing {
                        Task { await model.setSystemVolume(String(Int(systemVolumeDraft.rounded()))) }
                    }
                }
            )
            .controlSize(.small)
            .tint(.secondary)
            .disabled(!model.canSendCommands)
            .accessibilityLabel("Beast system volume")

            Image(systemName: "hifispeaker.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text("\(Int(systemVolumeDraft.rounded()))")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }
}
