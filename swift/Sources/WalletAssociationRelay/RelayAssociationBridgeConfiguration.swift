import Foundation
import WalletAssociationCore

public struct RelayAssociationBridgeConfiguration: Sendable {
    public var walletName: String
    public var walletVersion: String
    public var supportedChains: [String]
    public var supportedFeatures: [String]
    public var sessionTokenTtlSeconds: Int
    public var maxPendingHandshakes: Int

    public init(
        walletName: String = "Native",
        walletVersion: String = "1.0.0",
        supportedChains: [String] = AssociationProtocol.supportedChains,
        supportedFeatures: [String] = AssociationProtocol.supportedFeatures,
        sessionTokenTtlSeconds: Int = AssociationProtocol.sessionTokenTtlSeconds,
        maxPendingHandshakes: Int = 256
    ) {
        self.walletName = walletName
        self.walletVersion = walletVersion
        self.supportedChains = supportedChains
        self.supportedFeatures = supportedFeatures
        self.sessionTokenTtlSeconds = sessionTokenTtlSeconds
        self.maxPendingHandshakes = maxPendingHandshakes
    }
}
