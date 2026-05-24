import Foundation

public enum AssociationAuthorizationRegistry {
    public static func upsertSession(
        origin: String,
        metadata: AssociationRequestMetadata?,
        session: AssociationSessionAuthorization,
        in authorizations: inout [AssociationOriginAuthorization],
        now: Date = Date()
    ) {
        if let index = authorizations.firstIndex(where: { $0.origin == origin }) {
            authorizations[index].displayName = metadata?.appName ?? URL(string: origin)?.host
            authorizations[index].lastConnectedAt = now
            authorizations[index].sessions.removeAll { $0.sessionId == session.sessionId }
            authorizations[index].sessions.append(session)
        } else {
            authorizations.append(AssociationOriginAuthorization(
                origin: origin,
                displayName: metadata?.appName ?? URL(string: origin)?.host,
                firstConnectedAt: now,
                lastConnectedAt: now,
                sessions: [session]
            ))
        }
    }

    public static func requireSession(
        origin: String,
        sessionId: String,
        in authorizations: [AssociationOriginAuthorization]
    ) throws -> AssociationSessionAuthorization {
        guard let app = authorizations.first(where: { $0.origin == origin }),
              let session = app.sessions.first(where: { $0.sessionId == sessionId })
        else {
            throw WalletAssociationError.sessionNotFound
        }
        return session
    }

    public static func recordUse(
        origin: String,
        sessionId: String,
        in authorizations: inout [AssociationOriginAuthorization],
        now: Date = Date()
    ) {
        guard let appIndex = authorizations.firstIndex(where: { $0.origin == origin }),
              let sessionIndex = authorizations[appIndex].sessions.firstIndex(where: { $0.sessionId == sessionId })
        else {
            return
        }
        authorizations[appIndex].lastConnectedAt = now
        authorizations[appIndex].sessions[sessionIndex].lastConnectedAt = now
    }

    @discardableResult
    public static func revokeSession(
        origin: String,
        sessionId: String,
        in authorizations: inout [AssociationOriginAuthorization]
    ) -> [String] {
        guard let index = authorizations.firstIndex(where: { $0.origin == origin }) else { return [] }
        let revoked = authorizations[index].sessions.filter { $0.sessionId == sessionId }.map(\.sessionId)
        authorizations[index].sessions.removeAll { $0.sessionId == sessionId }
        authorizations[index].lastConnectedAt = authorizations[index].sessions.map(\.lastConnectedAt).max()
            ?? authorizations[index].lastConnectedAt
        if authorizations[index].sessions.isEmpty {
            authorizations.remove(at: index)
        }
        return revoked
    }

    @discardableResult
    public static func revokeOrigin(
        origin: String,
        in authorizations: inout [AssociationOriginAuthorization]
    ) -> [String] {
        let revoked = authorizations.first(where: { $0.origin == origin })?.sessions.map(\.sessionId) ?? []
        authorizations.removeAll { $0.origin == origin }
        return revoked
    }
}

