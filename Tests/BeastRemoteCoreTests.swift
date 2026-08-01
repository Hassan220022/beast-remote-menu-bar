import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func expectNil<T>(_ actual: T?, _ message: String) throws {
    guard actual == nil else {
        throw TestFailure(description: "\(message): expected nil, got \(String(describing: actual))")
    }
}

func expectNotNil<T>(_ actual: T?, _ message: String) throws -> T {
    guard let actual else {
        throw TestFailure(description: "\(message): expected value, got nil")
    }
    return actual
}

func testFormatTime() throws {
    try expectEqual(formatTime(0), "0:00", "zero seconds")
    try expectEqual(formatTime(65.9), "1:05", "minute formatting floors seconds")
    try expectEqual(formatTime(3661), "1:01:01", "hour formatting")
    try expectEqual(formatTime(.nan), "--:--", "invalid time formatting")
}

func testParseDuration() throws {
    try expectEqual(parseDuration("3:45"), 225, "mm:ss duration")
    try expectEqual(parseDuration("1:02:03"), 3723, "hh:mm:ss duration")
    try expectNil(parseDuration("not a duration"), "invalid duration")
    try expectNil(parseDuration("1"), "partial duration")
}

func testSnapshotFromRemoteState() throws {
    let state = RemoteState(
        player: RemotePlayer(
            trackState: 1,
            videoProgress: 42,
            volume: 74,
            muted: false,
            queue: RemoteQueue(
                items: [
                    RemoteQueueItem(title: "First", author: "Artist A", duration: "1:00", selected: false, videoId: "a", thumbnails: nil),
                    RemoteQueueItem(title: "Second", author: "Artist B", duration: "2:30", selected: true, videoId: "b", thumbnails: [
                        RemoteThumbnail(url: "https://example.test/small.jpg", width: 10, height: 10),
                        RemoteThumbnail(url: "https://example.test/large.jpg", width: 100, height: 100),
                    ]),
                ],
                automixItems: [
                    RemoteQueueItem(title: "Auto", author: "Artist C", duration: nil, selected: nil, videoId: nil, thumbnails: nil),
                ],
                repeatMode: 1,
                selectedItemIndex: nil
            ),
            videoDetails: nil
        ),
        video: nil,
        playlistId: "playlist-1"
    )

    let snapshot = try expectNotNil(BeastMediaSnapshot.from(state: state), "snapshot")
    try expectEqual(snapshot.title, "Second", "selected title")
    try expectEqual(snapshot.author, "Artist B", "selected author")
    try expectEqual(snapshot.durationSeconds, 150, "selected duration")
    try expectEqual(snapshot.artworkUrl, "https://example.test/large.jpg", "largest artwork")
    try expectEqual(snapshot.queueIndex, 1, "selected queue index")
    try expectEqual(snapshot.queueLength, 3, "queue length includes automix")
    try expectEqual(snapshot.statusText, "Playing", "playing status")
    try expectEqual(snapshot.repeatText, "Repeat: all", "repeat status")
    try expectEqual(snapshot.volumeText, "Volume 74", "volume status")
}

func testValidBaseURL() throws {
    _ = try expectNotNil(BeastRemoteModel.validBaseURL(from: "http://h:1"), "http url with port")
    _ = try expectNotNil(BeastRemoteModel.validBaseURL(from: "https://beast.local"), "https url with host")
    try expectNil(BeastRemoteModel.validBaseURL(from: "ftp://h"), "rejects ftp scheme")
    try expectNil(BeastRemoteModel.validBaseURL(from: "notaurl"), "rejects scheme-less string")
    try expectNil(BeastRemoteModel.validBaseURL(from: "http://"), "rejects missing host")
    try expectNil(BeastRemoteModel.validBaseURL(from: ""), "rejects empty string")
}

func testOptimisticSnapshotPatches() throws {
    let base = BeastMediaSnapshot(
        title: "T",
        author: "A",
        album: nil,
        artworkUrl: nil,
        videoId: "v1",
        playlistId: nil,
        trackState: 1,
        isPlaying: true,
        muted: false,
        volume: 40,
        systemVolume: 50,
        systemMuted: false,
        repeatMode: 0,
        durationSeconds: 100,
        progressSeconds: 10,
        fetchedAt: 1,
        queueIndex: 0,
        queueLength: 2
    )
    let paused = base.togglingPlayState()
    try expectEqual(paused.isPlaying, false, "toggle pauses")
    try expectEqual(paused.trackState, 0, "toggle trackState")
    let muted = base.withMuted(true)
    try expectEqual(muted.muted, true, "mute")
    let vol = base.withVolume(12)
    try expectEqual(vol.volume, 12, "volume")
    try expectEqual(vol.muted, false, "volume keeps mute flag")
    let mutedBase = base.withMuted(true).withVolume(12)
    try expectEqual(mutedBase.muted, true, "setVolume does not unmute")
    let sysVol = base.withSystemVolume(77)
    try expectEqual(sysVol.systemVolume, 77, "system volume")
    try expectEqual(sysVol.systemMuted, false, "system volume unmutes")
    let sysMuted = base.withSystemMuted(true)
    try expectEqual(sysMuted.systemMuted, true, "system mute")
    let fromTrack = BeastMediaSnapshot(
        title: "T", author: "A", album: nil, artworkUrl: nil, videoId: "v1", playlistId: nil,
        trackState: 1, isPlaying: nil, muted: false, volume: 1, systemVolume: nil, systemMuted: nil,
        repeatMode: 0,
        durationSeconds: 1, progressSeconds: 0, fetchedAt: 1, queueIndex: 0, queueLength: 1
    ).togglingPlayState()
    try expectEqual(fromTrack.isPlaying, false, "toggle uses trackState when isPlaying nil")
}

let coreTests: [(String, () throws -> Void)] = [
    ("formatTime", testFormatTime),
    ("parseDuration", testParseDuration),
    ("snapshotFromRemoteState", testSnapshotFromRemoteState),
    ("validBaseURL", testValidBaseURL),
    ("optimisticSnapshotPatches", testOptimisticSnapshotPatches),
]
