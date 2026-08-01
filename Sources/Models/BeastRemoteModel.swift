import Combine
import Foundation

// Observable store backing the menu bar UI. Holds connection/media state and
// owns the polling lifecycle (resume/pause). Networking verbs live in
// BeastRemoteModel+API.swift; base-URL validation in URLValidation.swift.
@MainActor
final class BeastRemoteModel: ObservableObject {
    @Published var connected = false
    @Published var connectionText = "Checking Beast..."
    @Published var statusDetail = "Waiting for the first sync."
    @Published var media: BeastMediaSnapshot?
    @Published var systemVolume: Double?
    @Published var systemMuted: Bool?

    let rawBaseURL: String
    let baseURL: URL?
    let authToken: String?
    let session: URLSession
    private var refreshTask: Task<Void, Never>?
    private var popoverOpen = false
    /// >0 while a command round-trip is open. Poll refresh must not overwrite
    /// optimistic media during the companion's ~5s command window.
    /// Internal so BeastRemoteModel+API can bump it.
    var commandsInFlight = 0
    /// Monotonic command id so late responses cannot clobber newer media.
    var commandGeneration = 0

    /// Fast cadence while the popover is open.
    static let activePollInterval: UInt64 = 2_000_000_000
    /// Slow baseline cadence so state never goes fully stale when closed.
    static let idlePollInterval: UInt64 = 15_000_000_000

    var isConfigured: Bool { baseURL != nil }
    var canSendCommands: Bool { isConfigured && connected }

    init() {
        rawBaseURL = ProcessInfo.processInfo.environment["BEAST_REMOTE_URL"] ?? "http://192.168.1.99:8787"
        baseURL = Self.validBaseURL(from: rawBaseURL)

        let rawToken = ProcessInfo.processInfo.environment["BEAST_REMOTE_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        authToken = (rawToken?.isEmpty == false) ? rawToken : nil

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 12
        session = URLSession(configuration: configuration)

        if baseURL == nil {
            connected = false
            connectionText = "Invalid Beast URL"
            statusDetail = "BEAST_REMOTE_URL must be a valid http(s) URL with a host."
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Starts the always-on polling loop. Safe to call repeatedly — no-ops if
    /// already running. Polls at idle cadence when popover is closed, fast
    /// cadence when open, so data is never fully stale on reopen.
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.popoverOpen
                    ? Self.activePollInterval
                    : Self.idlePollInterval
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    /// Popover opened: switch to fast cadence and force an immediate refresh.
    func resume() {
        popoverOpen = true
        start()
        Task { await refresh() }
    }

    /// Popover closed: drop to slow baseline — loop keeps running in background.
    func pause() {
        popoverOpen = false
    }
}
