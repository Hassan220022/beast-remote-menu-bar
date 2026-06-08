import SwiftUI

// Hero artwork: centered ~150pt album art with continuous corner radius, soft
// shadow, and a material placeholder. Crossfades on track change via .id().
extension BeastMenuView {
    var heroArtwork: some View {
        let radius: CGFloat = 18
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                if let artworkURL = model.media?.artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .controlSize(.large)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        case .failure:
                            heroPlaceholder
                        @unknown default:
                            heroPlaceholder
                        }
                    }
                } else {
                    heroPlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(width: 150, height: 150)
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .id(model.media?.identity ?? "placeholder")
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.4), value: model.media?.identity ?? "placeholder")
            .accessibilityLabel("Album artwork")
    }

    var heroPlaceholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
