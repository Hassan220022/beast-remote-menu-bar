import Foundation

// Raw, Decodable DTOs mirroring the Beast `api/state` JSON. These are the wire
// format; the UI-facing projection is BeastMediaSnapshot (see its
// `from(state:)` for how these collapse into a single snapshot).

struct StateEnvelope: Decodable {
    let ok: Bool?
    let state: RemoteState?
    let media: BeastMediaSnapshot?
    let error: String?
    let warning: String?
    let cached: Bool?
}

/// Command POST response. Server may include an optimistic `media` snapshot so the
/// UI can update before the next full state poll (companion rate-limits ~5s).
struct CommandEnvelope: Decodable {
    let ok: Bool?
    let media: BeastMediaSnapshot?
    let error: String?
}

struct RemoteState: Decodable {
    let player: RemotePlayer?
    let video: RemoteVideoDetails?
    let playlistId: String?
}

struct RemotePlayer: Decodable {
    let trackState: Int?
    let videoProgress: Double?
    let volume: Double?
    let muted: Bool?
    let queue: RemoteQueue?
    let videoDetails: RemoteVideoDetails?
}

struct RemoteQueue: Decodable {
    let items: [RemoteQueueItem]?
    let automixItems: [RemoteQueueItem]?
    let repeatMode: Int?
    let selectedItemIndex: Int?
}

struct RemoteQueueItem: Decodable {
    let title: String?
    let author: String?
    let duration: String?
    let selected: Bool?
    let videoId: String?
    let thumbnails: [RemoteThumbnail]?
}

struct RemoteVideoDetails: Decodable {
    let title: String?
    let author: String?
    let album: String?
    let durationSeconds: Double?
    let id: String?
    let thumbnails: [RemoteThumbnail]?
}

struct RemoteThumbnail: Decodable {
    let url: String?
    let width: Double?
    let height: Double?
}
