import SwiftUI

// Seek section: a 1s-cadence TimelineView drives the slider thumb and time
// labels to track live playback while the user is not dragging. Editing pins
// the draft and commits a seek on release.
extension BeastMenuView {
    func seekSection(for media: BeastMediaSnapshot) -> some View {
        let duration = media.durationSeconds ?? 0
        let upperBound = max(duration, 1)

        // Drive a ~1s cadence so the slider thumb and time label track live
        // playback while the user is not dragging. Each tick recomputes the
        // position from the existing progress(for:) logic (no duplicated math),
        // and pushes it into seekDraft only when !isSeeking and playing.
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            let live = progress(for: media)
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Slider(
                        value: Binding(
                            get: { seekDraft },
                            set: { seekDraft = $0 }
                        ),
                        in: 0...upperBound,
                        onEditingChanged: { editing in
                            isSeeking = editing
                            if editing {
                                seekDraft = live
                            } else {
                                Task { await model.seek(to: seekDraft) }
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(.accentColor)
                    .disabled(duration <= 0 || !model.canSendCommands)
                    .accessibilityLabel("Seek")

                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }

                HStack {
                    Text(formatTime(isSeeking ? seekDraft : live))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(duration > 0 ? formatTime(duration) : "--:--")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: live) { _, newValue in
                if !isSeeking, model.media?.isPlaying == true {
                    seekDraft = newValue
                }
            }
        }
    }
}
