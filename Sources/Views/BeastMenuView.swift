import SwiftUI

// The popover's root view. Owns all interactive draft state (seek/volume/url)
// and the polling lifecycle hooks; each visual section is implemented in a
// sibling file as an extension on this type (Header, HeroArtwork, TrackInfo,
// Seek, Transport, Volume, SecondaryControls, LoadURL, Footer, AmbientBackdrop).
struct BeastMenuView: View {
    @ObservedObject var model: BeastRemoteModel
    @State var seekDraft = 0.0
    @State var isSeeking = false
    @State var urlDraft = ""
    @State var volumeDraft = 0.0
    @State var isAdjustingVolume = false
    @State var playPressed = false

    let panelWidth: CGFloat = 360
    let panelHeight: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            ScrollView {
                VStack(spacing: 16) {
                    heroArtwork
                    trackInfo
                    if let media = model.media {
                        seekSection(for: media)
                        transportSection
                        volumeSection(for: media)
                        secondaryControls
                    } else {
                        emptyStateCard
                    }
                    loadURLSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            footerSection
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(ambientBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            syncSeekDraft()
            syncVolumeDraft()
            // Popover opened: start live polling so transport state stays fresh.
            model.resume()
        }
        .onDisappear {
            // Popover closed: stop polling to save network/battery.
            model.pause()
        }
        .onChange(of: model.media?.identity ?? "") { _, _ in
            if !isSeeking {
                syncSeekDraft()
            }
            if !isAdjustingVolume {
                syncVolumeDraft()
            }
        }
    }
}
