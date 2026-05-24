import Foundation

public protocol AssociationSessionTokenStore: Sendable {
    func store(sessionId: String, token: Data) throws
    func load(sessionId: String) throws -> Data
    func delete(sessionId: String) throws
    func deleteAll(sessionIds: [String]) throws
}

public extension AssociationSessionTokenStore {
    func deleteAll(sessionIds: [String]) throws {
        for sessionId in sessionIds {
            try delete(sessionId: sessionId)
        }
    }
}

