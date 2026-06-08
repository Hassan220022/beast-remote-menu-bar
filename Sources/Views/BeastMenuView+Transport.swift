import SwiftUI

// Transport controls: previous / play-pause (with press-scale animation) / next.
extension BeastMenuView {
    var transportSection: some View {
        HStack(spacing: 36) {
            Spacer(minLength: 0)

            transportButton("backward.fill", label: "Previous", size: 22) {
                Task { await model.command("previous") }
            }

            Button {
                playPressed = true
                Task {
                    await model.command("playPause")
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    playPressed = false
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 10, x: 0, y: 4)
                    Image(systemName: model.media?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(playPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: playPressed)
            .disabled(!model.canSendCommands)
            .accessibilityLabel(model.media?.isPlaying == true ? "Pause" : "Play")
            .help(model.media?.isPlaying == true ? "Pause" : "Play")

            transportButton("forward.fill", label: "Next", size: 22) {
                Task { await model.command("next") }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    func transportButton(_ systemName: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(model.canSendCommands ? Color.primary : Color.secondary)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSendCommands)
        .accessibilityLabel(label)
        .help(label)
    }
}
