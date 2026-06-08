import Foundation

// Base-URL validation for BEAST_REMOTE_URL. `nonisolated` + `static` so it can
// run during init (before the actor is fully formed) and in tests without a
// model instance. Accepts only http/https URLs that include a host.
extension BeastRemoteModel {
    nonisolated static func validBaseURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
