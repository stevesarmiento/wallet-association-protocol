import Foundation

public struct AssociationDiscoverResponse: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let protocolVersion: String
    public let transports: [AssociationTransportDescriptor]
    public let chains: [String]
    public let features: [String]
    public let encryption: String
    public let sessionTokenTtlSeconds: Int

    public init(
        name: String,
        version: String,
        protocolVersion: String,
        transports: [AssociationTransportDescriptor],
        chains: [String],
        features: [String],
        encryption: String,
        sessionTokenTtlSeconds: Int
    ) {
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
        self.transports = transports
        self.chains = chains
        self.features = features
        self.encryption = encryption
        self.sessionTokenTtlSeconds = sessionTokenTtlSeconds
    }
}

public struct AssociationHandshakeRequest: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let dappPublicKeyBase64: String
    public let metadata: AssociationRequestMetadata?

    public init(protocolVersion: String, dappPublicKeyBase64: String, metadata: AssociationRequestMetadata? = nil) {
        self.protocolVersion = protocolVersion
        self.dappPublicKeyBase64 = dappPublicKeyBase64
        self.metadata = metadata
    }
}

public struct AssociationHandshakeResponse: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let handshakeId: String
    public let walletPublicKeyBase64: String
    public let expiresAt: Date

    public init(protocolVersion: String, handshakeId: String, walletPublicKeyBase64: String, expiresAt: Date) {
        self.protocolVersion = protocolVersion
        self.handshakeId = handshakeId
        self.walletPublicKeyBase64 = walletPublicKeyBase64
        self.expiresAt = expiresAt
    }
}

public enum AssociationRequestKind: String, Codable, Equatable, Sendable {
    case create
    case resume
}

public struct AssociationRequestPayload: Codable, Equatable, Sendable {
    public let kind: AssociationRequestKind
    public let requestedChains: [String]?
    public let requestedFeatures: [String]?
    public let resumeSessionId: String?
    public let resumeSessionTokenBase64: String?

    public init(
        kind: AssociationRequestKind,
        requestedChains: [String]? = nil,
        requestedFeatures: [String]? = nil,
        resumeSessionId: String? = nil,
        resumeSessionTokenBase64: String? = nil
    ) {
        self.kind = kind
        self.requestedChains = requestedChains
        self.requestedFeatures = requestedFeatures
        self.resumeSessionId = resumeSessionId
        self.resumeSessionTokenBase64 = resumeSessionTokenBase64
    }
}

public struct BridgeAccountResponse: Codable, Equatable, Sendable {
    public let address: String
    public let publicKey: [UInt8]
    public let chains: [String]
    public let features: [String]
    public let label: String?
    public let icon: String?

    public init(
        address: String,
        publicKey: [UInt8],
        chains: [String],
        features: [String],
        label: String? = nil,
        icon: String? = nil
    ) {
        self.address = address
        self.publicKey = publicKey
        self.chains = chains
        self.features = features
        self.label = label
        self.icon = icon
    }
}

public struct AssociationResponsePayload: Codable, Equatable, Sendable {
    public let sessionId: String
    public let sessionTokenBase64: String
    public let expiresAt: Date
    public let accounts: [BridgeAccountResponse]
    public let chains: [String]
    public let features: [String]
    public let signingPolicy: AssociationSigningPolicy

    public init(
        sessionId: String,
        sessionTokenBase64: String,
        expiresAt: Date,
        accounts: [BridgeAccountResponse],
        chains: [String],
        features: [String],
        signingPolicy: AssociationSigningPolicy
    ) {
        self.sessionId = sessionId
        self.sessionTokenBase64 = sessionTokenBase64
        self.expiresAt = expiresAt
        self.accounts = accounts
        self.chains = chains
        self.features = features
        self.signingPolicy = signingPolicy
    }
}

public enum AssociationRPCParams: Codable, Equatable, Sendable {
    case signMessage(AssociationSignMessageParams)
    case signTransaction(AssociationSignTransactionParams)
    case sessionRotation(AssociationSessionRotationRequest)

    private enum CodingKeys: String, CodingKey {
        case accountAddress
        case chain
        case messageBase64
        case transactionBase64
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let messageBase64 = try container.decodeIfPresent(String.self, forKey: .messageBase64) {
            self = .signMessage(AssociationSignMessageParams(
                accountAddress: try container.decode(String.self, forKey: .accountAddress),
                chain: try container.decodeIfPresent(String.self, forKey: .chain),
                messageBase64: messageBase64
            ))
            return
        }
        if let transactionBase64 = try container.decodeIfPresent(String.self, forKey: .transactionBase64) {
            self = .signTransaction(AssociationSignTransactionParams(
                accountAddress: try container.decode(String.self, forKey: .accountAddress),
                chain: try container.decodeIfPresent(String.self, forKey: .chain),
                transactionBase64: transactionBase64
            ))
            return
        }
        if let reason = try container.decodeIfPresent(String.self, forKey: .reason) {
            self = .sessionRotation(AssociationSessionRotationRequest(reason: reason))
            return
        }
        throw WalletAssociationError.malformedRequest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .signMessage(let params):
            try container.encode(params.accountAddress, forKey: .accountAddress)
            try container.encodeIfPresent(params.chain, forKey: .chain)
            try container.encode(params.messageBase64, forKey: .messageBase64)
        case .signTransaction(let params):
            try container.encode(params.accountAddress, forKey: .accountAddress)
            try container.encodeIfPresent(params.chain, forKey: .chain)
            try container.encode(params.transactionBase64, forKey: .transactionBase64)
        case .sessionRotation(let params):
            try container.encode(params.reason, forKey: .reason)
        }
    }
}

public struct AssociationSignMessageParams: Codable, Equatable, Sendable {
    public let accountAddress: String
    public let chain: String?
    public let messageBase64: String

    public init(accountAddress: String, chain: String? = nil, messageBase64: String) {
        self.accountAddress = accountAddress
        self.chain = chain
        self.messageBase64 = messageBase64
    }
}

public struct AssociationSignTransactionParams: Codable, Equatable, Sendable {
    public let accountAddress: String
    public let chain: String?
    public let transactionBase64: String

    public init(accountAddress: String, chain: String? = nil, transactionBase64: String) {
        self.accountAddress = accountAddress
        self.chain = chain
        self.transactionBase64 = transactionBase64
    }
}

public struct AssociationRPCRequestPayload: Codable, Equatable, Sendable {
    public let requestId: String
    public let issuedAt: Date
    public let sessionTokenBase64: String
    public let method: String
    public let params: AssociationRPCParams

    public init(
        requestId: String,
        issuedAt: Date,
        sessionTokenBase64: String,
        method: String,
        params: AssociationRPCParams
    ) {
        self.requestId = requestId
        self.issuedAt = issuedAt
        self.sessionTokenBase64 = sessionTokenBase64
        self.method = method
        self.params = params
    }
}

public enum AssociationRPCResult: Codable, Equatable, Sendable {
    case signMessage(AssociationSignMessageResponse)
    case signTransaction(AssociationSignTransactionResponse)
    case sessionRotation(AssociationSessionRotationResponse)

    private enum CodingKeys: String, CodingKey {
        case signatureBase64
        case signedTransactionBase64
        case signature
        case sessionId
        case sessionTokenBase64
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let signedTransactionBase64 = try container.decodeIfPresent(String.self, forKey: .signedTransactionBase64) {
            self = .signTransaction(AssociationSignTransactionResponse(
                signedTransactionBase64: signedTransactionBase64,
                signature: try container.decode(String.self, forKey: .signature)
            ))
            return
        }
        if let sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) {
            self = .sessionRotation(AssociationSessionRotationResponse(
                sessionId: sessionId,
                sessionTokenBase64: try container.decode(String.self, forKey: .sessionTokenBase64),
                expiresAt: try container.decode(Date.self, forKey: .expiresAt)
            ))
            return
        }
        self = .signMessage(AssociationSignMessageResponse(
            signatureBase64: try container.decode(String.self, forKey: .signatureBase64)
        ))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .signMessage(let response):
            try container.encode(response.signatureBase64, forKey: .signatureBase64)
        case .signTransaction(let response):
            try container.encode(response.signedTransactionBase64, forKey: .signedTransactionBase64)
            try container.encode(response.signature, forKey: .signature)
        case .sessionRotation(let response):
            try container.encode(response.sessionId, forKey: .sessionId)
            try container.encode(response.sessionTokenBase64, forKey: .sessionTokenBase64)
            try container.encode(response.expiresAt, forKey: .expiresAt)
        }
    }
}

public struct AssociationRPCResponsePayload: Codable, Equatable, Sendable {
    public let requestId: String
    public let result: AssociationRPCResult

    public init(requestId: String, result: AssociationRPCResult) {
        self.requestId = requestId
        self.result = result
    }
}

public struct AssociationSignMessageResponse: Codable, Equatable, Sendable {
    public let signatureBase64: String

    public init(signatureBase64: String) {
        self.signatureBase64 = signatureBase64
    }
}

public struct AssociationSignTransactionResponse: Codable, Equatable, Sendable {
    public let signedTransactionBase64: String
    public let signature: String

    public init(signedTransactionBase64: String, signature: String) {
        self.signedTransactionBase64 = signedTransactionBase64
        self.signature = signature
    }
}

public struct AssociationSessionRotationRequest: Codable, Equatable, Sendable {
    public let reason: String

    public init(reason: String = "dapp_requested") {
        self.reason = reason
    }
}

public struct AssociationSessionRotationResponse: Codable, Equatable, Sendable {
    public let sessionId: String
    public let sessionTokenBase64: String
    public let expiresAt: Date

    public init(sessionId: String, sessionTokenBase64: String, expiresAt: Date) {
        self.sessionId = sessionId
        self.sessionTokenBase64 = sessionTokenBase64
        self.expiresAt = expiresAt
    }
}

public enum AssociationSessionEventType: String, Codable, Equatable, Sendable {
    case sessionRevoked = "session_revoked"
    case accountsChanged = "accounts_changed"
    case chainsChanged = "chains_changed"
    case featuresChanged = "features_changed"
    case walletLocked = "wallet_locked"
    case walletUnlocked = "wallet_unlocked"
}

public struct AssociationSessionEventPayload: Codable, Equatable, Sendable {
    public let eventId: String
    public let issuedAt: Date
    public let sessionTokenBase64: String
    public let type: AssociationSessionEventType
    public let accounts: [BridgeAccountResponse]?
    public let chains: [String]?
    public let features: [String]?

    public init(
        eventId: String,
        issuedAt: Date = Date(),
        sessionTokenBase64: String,
        type: AssociationSessionEventType,
        accounts: [BridgeAccountResponse]? = nil,
        chains: [String]? = nil,
        features: [String]? = nil
    ) {
        self.eventId = eventId
        self.issuedAt = issuedAt
        self.sessionTokenBase64 = sessionTokenBase64
        self.type = type
        self.accounts = accounts
        self.chains = chains
        self.features = features
    }
}
