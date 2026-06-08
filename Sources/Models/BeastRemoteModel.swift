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

    let rawBaseURL: String
    let baseURL: URL?
    let authToken: String?
    let session: URLSession
    private var refreshTask: Task<Void, Never>?

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

    /// Starts (or restarts) the periodic 30s polling loop. Safe to call
    /// repeatedly: it no-ops while a loop is already running. The loop refreshes
    /// immediately so the UI is live as soon as the popover opens.
    func resume() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    /// Cancels the polling loop so we stop hitting the network/battery while the
    /// popover is closed. `resume()` brings it back.
    func pause() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
