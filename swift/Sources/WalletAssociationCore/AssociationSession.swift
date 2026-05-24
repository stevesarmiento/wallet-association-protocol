import Foundation

public struct AssociationHandshakeContext: Equatable, Sendable {
    public let handshakeId: String
    public let origin: String
    public let dappPublicKeyBase64: String
    public let metadata: AssociationRequestMetadata?

    public init(
        handshakeId: String,
        origin: String,
        dappPublicKeyBase64: String,
        metadata: AssociationRequestMetadata?
    ) {
        self.handshakeId = handshakeId
        self.origin = origin
        self.dappPublicKeyBase64 = dappPublicKeyBase64
        self.metadata = metadata
    }
}

public struct AssociationSessionContext: Equatable, Sendable {
    public let sessionId: String
    public let origin: String

    public init(sessionId: String, origin: String) {
        self.sessionId = sessionId
        self.origin = origin
    }
}

public struct AssociationSessionToken: Equatable, Sendable {
    public let token: Data

    public init(token: Data) {
        self.token = token
    }
}
