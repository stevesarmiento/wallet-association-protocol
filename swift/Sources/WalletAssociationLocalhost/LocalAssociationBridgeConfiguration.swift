import Foundation
import WalletAssociationCore

public struct LocalAssociationBridgeConfiguration: Sendable {
    public var port: UInt16
    public var walletName: String
    public var walletVersion: String
    public var supportedChains: [String]
    public var supportedFeatures: [String]
    public var sessionTokenTtlSeconds: Int
    public var maxRequestBytes: Int
    public var maxBodyBytes: Int
    public var maxPendingHandshakes: Int

    public init(
        port: UInt16 = AssociationProtocol.defaultPort,
        walletName: String = "Native",
        walletVersion: String = "1.0.0",
        supportedChains: [String] = AssociationProtocol.supportedChains,
        supportedFeatures: [String] = AssociationProtocol.supportedFeatures,
        sessionTokenTtlSeconds: Int = AssociationProtocol.sessionTokenTtlSeconds,
        maxRequestBytes: Int = 64 * 1024,
        maxBodyBytes: Int = 48 * 1024,
        maxPendingHandshakes: Int = 256
    ) {
        self.port = port
        self.walletName = walletName
        self.walletVersion = walletVersion
        self.supportedChains = supportedChains
        self.supportedFeatures = supportedFeatures
        self.sessionTokenTtlSeconds = sessionTokenTtlSeconds
        self.maxRequestBytes = maxRequestBytes
        self.maxBodyBytes = maxBodyBytes
        self.maxPendingHandshakes = maxPendingHandshakes
    }
}
