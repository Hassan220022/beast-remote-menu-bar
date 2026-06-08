import Foundation

// UI-facing projection of the current track. Decoded directly from the `media`
// field when present, or collapsed from a RemoteState via `from(state:)`. The
// derived strings (statusText, queueSummary, ...) keep formatting out of views.
struct BeastMediaSnapshot: Decodable {
    let title: String
    let author: String
    let album: String?
    let artworkUrl: String?
    let videoId: String?
    let playlistId: String?
    let trackState: Int?
    let isPlaying: Bool?
    let muted: Bool?
    let volume: Double?
    let repeatMode: Int?
    let durationSeconds: Double?
    let progressSeconds: Double?
    let fetchedAt: Double?
    let queueIndex: Int?
    let queueLength: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case author
        case album
        case artworkUrl
        case videoId
        case playlistId
        case trackState
        case isPlaying
        case muted
        case volume
        case repeatMode
        case durationSeconds
        case progressSeconds
        case fetchedAt
        case queueIndex
        case queueLength
    }

    var identity: String {
        [videoId, title, author].compactMap { $0 }.joined(separator: "|")
    }

    var artworkURL: URL? {
        guard let artworkUrl else { return nil }
        return URL(string: artworkUrl)
    }

    var subtitle: String {
        let status = statusText
        if let album, !album.isEmpty {
            return [author, album, status].joined(separator: " · ")
        }
        return [author, status].joined(separator: " · ")
    }

    var statusText: String {
        switch trackState {
        case 1: return "Playing"
        case 0: return "Paused"
        case 2: return "Buffering"
        case -1: return "Unknown"
        default: return isPlaying == true ? "Playing" : "Idle"
        }
    }

    var repeatText: String {
        switch repeatMode {
        case 0: return "Repeat: off"
        case 1: return "Repeat: all"
        case 2: return "Repeat: one"
        default: return "Repeat: unknown"
        }
    }

    var volumeText: String {
        if let volume {
            return muted == true ? "Muted" : "Volume \(Int(volume.rounded()))"
        }
        return muted == true ? "Muted" : "Volume: --"
    }

    var queueSummary: String? {
        guard let queueLength, queueLength > 0 else { return nil }
        if let queueIndex {
            return "Queue \(queueIndex + 1)/\(queueLength)"
        }
        return "Queue \(queueLength)"
    }

    static func from(state: RemoteState?) -> BeastMediaSnapshot? {
        guard let state else { return nil }
        let player = state.player
        let queue = player?.queue
        let items = queue?.items ?? []
        let selectedIndex = queue?.selectedItemIndex ?? items.firstIndex(where: { $0.selected == true })
        let selectedItem = selectedIndex.flatMap { items.indices.contains($0) ? items[$0] : nil } ?? items.first
        let video = state.video ?? player?.videoDetails
        let thumbnails = video?.thumbnails ?? selectedItem?.thumbnails
        let artwork = thumbnails?.compactMap { thumbnail -> (String, Double) in
            guard let url = thumbnail.url else { return ( "", 0 ) }
            let width = thumbnail.width ?? 0
            let height = thumbnail.height ?? 0
            return (url, width * height)
        }.sorted(by: { $0.1 < $1.1 }).last?.0

        let durationSeconds = video?.durationSeconds ?? selectedItem.flatMap { parseDuration($0.duration) }
        let progressSeconds = player?.videoProgress ?? 0
        return BeastMediaSnapshot(
            title: video?.title ?? selectedItem?.title ?? "Nothing playing",
            author: video?.author ?? selectedItem?.author ?? "Unknown artist",
            album: video?.album,
            artworkUrl: artwork,
            videoId: video?.id ?? selectedItem?.videoId,
            playlistId: state.playlistId,
            trackState: player?.trackState,
            isPlaying: player?.trackState == 1,
            muted: player?.muted,
            volume: player?.volume,
            repeatMode: queue?.repeatMode,
            durationSeconds: durationSeconds,
            progressSeconds: progressSeconds,
            fetchedAt: Date().timeIntervalSince1970,
            queueIndex: selectedIndex,
            queueLength: items.count + (queue?.automixItems?.count ?? 0)
        )
    }
}
