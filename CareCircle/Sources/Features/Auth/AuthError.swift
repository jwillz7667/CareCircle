import Foundation

// MARK: - AuthError

enum AuthError: LocalizedError, Sendable, Equatable {
    case canceled
    case invalidCredential
    case credentialRevoked
    case nonceMismatch
    case keychainFailure(OSStatus)
    case invalidEmailOrPassword
    case emailAlreadyInUse
    case googleSignInUnavailable
    case googleSignInFailed(String)
    case backendUnavailable
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .canceled:
            "Sign in was canceled."
        case .invalidCredential:
            "Apple did not return a valid credential."
        case .credentialRevoked:
            "Your Apple credential is no longer valid. Please sign in again."
        case .nonceMismatch:
            "Sign in could not be verified. Please try again."
        case let .keychainFailure(status):
            "Could not access secure storage (code \(status))."
        case .invalidEmailOrPassword:
            "Email or password is incorrect."
        case .emailAlreadyInUse:
            "An account with this email already exists. Try signing in with the method you used before."
        case .googleSignInUnavailable:
            "Google sign-in isn't configured for this build."
        case let .googleSignInFailed(detail):
            detail
        case .backendUnavailable:
            "Could not reach the CareCircle server. Check your connection and try again."
        case let .unknown(message):
            message
        }
    }
}

// MARK: - KeychainError

enum KeychainError: LocalizedError, Sendable, Equatable {
    case unexpectedData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "Secure storage returned unexpected data."
        case let .unhandled(status):
            "Secure storage error (code \(status))."
        }
    }
}
