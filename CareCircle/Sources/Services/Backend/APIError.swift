import Foundation

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case notAuthenticated
    case transport(URLError)
    case decoding(Error)
    case http(status: Int, body: String?)
    case unauthorized
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not signed in to the backend."
        case let .transport(error):
            "Network error: \(error.localizedDescription)"
        case let .decoding(error):
            "Decoding error: \(error.localizedDescription)"
        case let .http(status, body):
            "HTTP \(status)\(body.map { ": \($0)" } ?? "")"
        case .unauthorized:
            "Session expired. Please sign in again."
        case .refreshFailed:
            "Could not refresh backend session."
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .unauthorized, .refreshFailed, .notAuthenticated:
            true
        default:
            false
        }
    }
}
