import SwiftUI

// Ambient backdrop: a heavily blurred, scaled, slightly saturated copy of the
// album art bleeds behind an ultraThinMaterial scrim so the popover takes on
// the track's color. Falls back to a neutral material when there is no artwork.
extension BeastMenuView {
    @ViewBuilder
    var ambientBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if let artworkURL = model.media?.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .saturation(1.4)
                            .blur(radius: 60, opaque: true)
                            .scaleEffect(1.6)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .id(model.media?.identity ?? "")
                .animation(.easeInOut(duration: 0.45), value: model.media?.identity ?? "")
            }

            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}
