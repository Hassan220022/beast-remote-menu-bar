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
                if let warning = snapshot.warning {
                    statusDetail = "Showing cached media: \(warning)"
                } else if let error = snapshot.error {
                    statusDetail = error
                } else {
                    statusDetail = "Live media synced from the Beast."
                }
                media = snapshot.media ?? BeastMediaSnapshot.from(state: snapshot.state)
            } else {
                connected = false
                connectionText = "Disconnected"
                statusDetail = snapshot.error ?? "Unknown error"
                media = nil
            }
        } catch {
            connected = false
            connectionText = "Disconnected: \(error.localizedDescription)"
            statusDetail = error.localizedDescription
            media = nil
        }
    }

    func command(_ name: String) async {
        do {
            _ = try await post(path: "api/command", body: ["command": name])
            statusDetail = "\(name) sent to Beast."
        } catch {
            statusDetail = "Command failed: \(error.localizedDescription)"
        }
    }

    func seek(to seconds: Double) async {
        guard seconds.isFinite else {
            statusDetail = "Seek requires a number."
            return
        }
        do {
            _ = try await post(path: "api/command", body: ["command": "seekTo", "data": seconds])
            statusDetail = "Seek sent to Beast."
        } catch {
            statusDetail = "Seek failed: \(error.localizedDescription)"
        }
    }

    func loadURL(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await post(path: "api/load-url", body: ["url": trimmed])
            statusDetail = "URL sent to Beast."
        } catch {
            statusDetail = "Load failed: \(error.localizedDescription)"
        }
    }

    func setVolume(_ value: String) async {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (0...100).contains(intValue) else {
            statusDetail = "Volume must be 0-100"
            return
        }
        do {
            _ = try await post(path: "api/command", body: ["command": "setVolume", "data": intValue])
            statusDetail = "Volume sent to Beast."
        } catch {
            statusDetail = "Volume failed: \(error.localizedDescription)"
        }
    }

    private func getState() async throws -> StateEnvelope {
        let request = try makeRequest(path: "api/state")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(StateEnvelope.self, from: data)
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
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
