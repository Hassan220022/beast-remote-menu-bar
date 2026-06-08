import Foundation

enum BeastRemoteError: LocalizedError {
    case invalidBaseURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid BEAST_REMOTE_URL: \(value)"
        }
    }
}
