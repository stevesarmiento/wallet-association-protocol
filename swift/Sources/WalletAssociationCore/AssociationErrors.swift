import Foundation

public enum WalletAssociationError: LocalizedError, Equatable {
    case invalidOrigin
    case unsupportedProtocol(String)
    case invalidHandshake
    case invalidEnvelope
    case sessionNotFound
    case sessionExpired
    case sessionTokenInvalid
    case replayDetected
    case unsupportedMethod(String)
    case malformedRequest
    case requestTooLarge
    case userRejected
    case unavailable(String)
    case secureRandomUnavailable(OSStatus)
    case keychainStoreFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidOrigin:
            "Association request origin is invalid."
        case .unsupportedProtocol(let version):
            "Unsupported association protocol version: \(version)."
        case .invalidHandshake:
            "Association handshake is invalid."
        case .invalidEnvelope:
            "Association encrypted envelope is invalid."
        case .sessionNotFound:
            "Association session was not found."
        case .sessionExpired:
            "Association session has expired."
        case .sessionTokenInvalid:
            "Association session token is invalid."
        case .replayDetected:
            "Association request replay detected."
        case .unsupportedMethod(let method):
            "Unsupported association RPC method: \(method)."
        case .malformedRequest:
            "Malformed association request."
        case .requestTooLarge:
            "Association request is too large."
        case .userRejected:
            "user rejected"
        case .unavailable(let message):
            message
        case .secureRandomUnavailable(let status):
            "Secure random values are unavailable: \(status)."
        case .keychainStoreFailed(let status):
            "Keychain store failed: \(status)."
        case .keychainReadFailed(let status):
            "Keychain read failed: \(status)."
        case .keychainDeleteFailed(let status):
            "Keychain delete failed: \(status)."
        }
    }
}
