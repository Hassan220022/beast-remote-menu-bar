import SwiftUI

// Track info block (title/author/album + status & queue labels) and the
// empty-state card shown when there's no media snapshot.
extension BeastMenuView {
    @ViewBuilder
    var trackInfo: some View {
        if let media = model.media {
            VStack(spacing: 4) {
                Text(media.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, isRTLText ? .rightToLeft : .leftToRight)

                Text(media.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, isRTLText ? .rightToLeft : .leftToRight)

                if let album = media.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Label(media.statusText, systemImage: media.isPlaying == true ? "waveform" : "pause.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(media.isPlaying == true ? Color.accentColor : .secondary)

                    if let queueSummary = media.queueSummary {
                        Label(queueSummary, systemImage: "list.bullet")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 4) {
                Text("Nothing playing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(model.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    var emptyStateCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
            Text(model.isConfigured ? "Open YouTube Music on Beast, then refresh." : "Set BEAST_REMOTE_URL to a valid http(s) URL.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
