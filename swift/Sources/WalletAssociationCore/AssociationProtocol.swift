import Foundation

public enum AssociationProtocol {
    public static let version = "2"
    public static let defaultPort: UInt16 = 51_884
    public static let sessionTokenTtlSeconds = 7 * 24 * 60 * 60
    public static let rpcClockSkewSeconds: TimeInterval = 60
    public static let handshakeTtlSeconds: TimeInterval = 5 * 60
    public static let encryption = "x25519-hkdf-sha256-chacha20poly1305"

    public static let supportedChains = [
        "solana:mainnet",
        "solana:devnet",
        "solana:testnet",
        "solana:localnet"
    ]

    public static let supportedFeatures = [
        "solana:signMessage",
        "solana:signTransaction"
    ]
}

public enum AssociationOperation: String, Codable, Equatable, Sendable {
    case discover
    case handshake
    case associate
    case rpc
}

public struct AssociationTransportDescriptor: Codable, Equatable, Sendable {
    public let type: String
    public let host: String?
    public let port: UInt16?

    public init(type: String, host: String? = nil, port: UInt16? = nil) {
        self.type = type
        self.host = host
        self.port = port
    }
}

public struct AssociationRequestMetadata: Codable, Equatable, Sendable {
    public let origin: String?
    public let appName: String?
    public let appIcon: String?

    public init(origin: String? = nil, appName: String? = nil, appIcon: String? = nil) {
        self.origin = origin
        self.appName = appName
        self.appIcon = appIcon
    }
}

public enum AssociationSigningPolicy: String, Codable, Equatable, Sendable {
    case prompt
    case allowWithoutPrompt
}
