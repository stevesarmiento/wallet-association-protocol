import Foundation

public struct AssociationOriginAuthorization: Codable, Equatable, Identifiable, Sendable {
    public var id: String { origin }
    public var origin: String
    public var displayName: String?
    public var firstConnectedAt: Date
    public var lastConnectedAt: Date
    public var sessions: [AssociationSessionAuthorization]

    private enum CodingKeys: String, CodingKey {
        case origin
        case displayName
        case firstConnectedAt
        case lastConnectedAt
        case sessions
    }

    public init(
        origin: String,
        displayName: String? = nil,
        firstConnectedAt: Date = Date(),
        lastConnectedAt: Date = Date(),
        sessions: [AssociationSessionAuthorization] = []
    ) {
        self.origin = origin
        self.displayName = displayName
        self.firstConnectedAt = firstConnectedAt
        self.lastConnectedAt = lastConnectedAt
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            origin: try container.decode(String.self, forKey: .origin),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            firstConnectedAt: try container.decodeIfPresent(Date.self, forKey: .firstConnectedAt) ?? Date(),
            lastConnectedAt: try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt) ?? Date(),
            sessions: try container.decodeIfPresent([AssociationSessionAuthorization].self, forKey: .sessions) ?? []
        )
    }
}

public struct AssociationSessionAuthorization: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sessionId }
    public var sessionId: String
    public var dappPublicKeyBase64: String
    public var appName: String?
    public var appIcon: String?
    public var transport: String
    public var firstConnectedAt: Date
    public var lastConnectedAt: Date
    public var expiresAt: Date
    public var signingPolicy: AssociationSigningPolicy

    public init(
        sessionId: String,
        dappPublicKeyBase64: String,
        appName: String? = nil,
        appIcon: String? = nil,
        transport: String = "localhost",
        firstConnectedAt: Date = Date(),
        lastConnectedAt: Date = Date(),
        expiresAt: Date,
        signingPolicy: AssociationSigningPolicy = .prompt
    ) {
        self.sessionId = sessionId
        self.dappPublicKeyBase64 = dappPublicKeyBase64
        self.appName = appName
        self.appIcon = appIcon
        self.transport = transport
        self.firstConnectedAt = firstConnectedAt
        self.lastConnectedAt = lastConnectedAt
        self.expiresAt = expiresAt
        self.signingPolicy = signingPolicy
    }
}

