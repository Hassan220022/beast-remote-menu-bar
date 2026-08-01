import Foundation

// Networking surface for `BeastRemoteModel`: the public refresh/command verbs
// the UI calls, plus the private request plumbing (auth header, endpoint
// resolution, status validation). Kept in an extension so the store's state and
// lifecycle stay readable in Sources/Models/BeastRemoteModel.swift.
extension BeastRemoteModel {
    func refresh() async {
        do {
            let snapshot = try await getState()
            if snapshot.ok == true {
                connected = true
                if snapshot.cached == true {
                    connectionText = "Connected to Beast · cached"
                } else {
                    connectionText = "Connected to Beast"
                }
                // Root cause of "UI stuck until close": 2s poll overwrites optimistic
                // media while a command is still waiting on the companion (~5s).
                if commandsInFlight > 0 {
                    return
                }
                if let warning = snapshot.warning {
                    statusDetail = "Showing cached media: \(warning)"
                } else if let error = snapshot.error {
                    statusDetail = error
                } else {
                    statusDetail = "Live media synced from the Beast."
                }
                let next = snapshot.media ?? BeastMediaSnapshot.from(state: snapshot.state)
                systemVolume = next?.systemVolume
                systemMuted = next?.systemMuted
                media = next
            } else {
                connected = false
                connectionText = "Disconnected"
                statusDetail = snapshot.error ?? "Unknown error"
                if commandsInFlight == 0 {
                    media = nil
                }
            }
        } catch {
            connected = false
            connectionText = "Disconnected: \(error.localizedDescription)"
            statusDetail = error.localizedDescription
            if commandsInFlight == 0 {
                media = nil
            }
        }
    }

    func command(_ name: String) async {
        let generation = beginCommand()
        applyOptimisticUpdate(for: name)
        do {
            let data = try await post(path: "api/command", body: ["command": name])
            applyCommandMedia(from: data, generation: generation)
            statusDetail = "\(name) sent to Beast."
        } catch {
            statusDetail = "Command failed: \(error.localizedDescription)"
        }
        endCommand()
        await refresh()
    }

    func seek(to seconds: Double) async {
        guard seconds.isFinite else {
            statusDetail = "Seek requires a number."
            return
        }
        let generation = beginCommand()
        do {
            let data = try await post(path: "api/command", body: ["command": "seekTo", "data": seconds])
            applyCommandMedia(from: data, generation: generation)
            statusDetail = "Seek sent to Beast."
        } catch {
            statusDetail = "Seek failed: \(error.localizedDescription)"
        }
        endCommand()
        await refresh()
    }

    func loadURL(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let generation = beginCommand()
        do {
            let data = try await post(path: "api/load-url", body: ["url": trimmed])
            applyCommandMedia(from: data, generation: generation)
            statusDetail = "URL sent to Beast."
        } catch {
            statusDetail = "Load failed: \(error.localizedDescription)"
        }
        endCommand()
        await refresh()
    }

    func setVolume(_ value: String) async {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (0...100).contains(intValue) else {
            statusDetail = "Volume must be 0-100"
            return
        }
        let generation = beginCommand()
        if let current = media {
            media = current.withVolume(Double(intValue))
        }
        do {
            let data = try await post(path: "api/command", body: ["command": "setVolume", "data": intValue])
            applyCommandMedia(from: data, generation: generation)
            statusDetail = "Volume sent to Beast."
        } catch {
            statusDetail = "Volume failed: \(error.localizedDescription)"
        }
        endCommand()
        await refresh()
    }

    func setSystemVolume(_ value: String) async {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (0...100).contains(intValue) else {
            statusDetail = "System volume must be 0-100"
            return
        }
        if let current = media {
            media = current.withSystemVolume(Double(intValue))
        }
        systemVolume = Double(intValue)
        do {
            let body = try JSONSerialization.data(withJSONObject: ["volume": intValue])
            _ = try await postRaw(path: "api/system-volume", body: body)
            statusDetail = "System volume sent to Beast."
        } catch {
            statusDetail = "System volume failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    func toggleSystemMute() async {
        let target = !(systemMuted == true)
        if let current = media {
            media = current.withSystemMuted(target)
        }
        systemMuted = target
        do {
            let body = try JSONSerialization.data(withJSONObject: ["muted": target])
            _ = try await postRaw(path: "api/system-mute", body: body)
            statusDetail = target ? "Beast muted." : "Beast unmuted."
        } catch {
            statusDetail = "System mute failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Instant local UI for commands we can project without queue data.
    private func applyOptimisticUpdate(for command: String) {
        guard let current = media else { return }
        switch command {
        case "playPause":
            media = current.togglingPlayState()
        case "mute":
            media = current.withMuted(true)
        case "unmute":
            media = current.withMuted(false)
        default:
            break
        }
    }

    private func beginCommand() -> Int {
        commandsInFlight += 1
        commandGeneration += 1
        return commandGeneration
    }

    private func endCommand() {
        commandsInFlight = max(0, commandsInFlight - 1)
    }

    private func applyCommandMedia(from data: Data, generation: Int) {
        guard generation == commandGeneration else { return }
        guard let envelope = try? JSONDecoder().decode(CommandEnvelope.self, from: data),
              let next = envelope.media else { return }
        media = next
    }

    private func getState() async throws -> StateEnvelope {
        let request = try makeRequest(path: "api/state")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(StateEnvelope.self, from: data)
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        try await postRaw(path: path, body: try JSONSerialization.data(withJSONObject: body, options: []))
    }

    private func postRaw(path: String, body: Data) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return data
    }

    private func makeRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let baseURL else {
            throw BeastRemoteError.invalidBaseURL(rawBaseURL)
        }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "BeastRemote", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
    }
}
