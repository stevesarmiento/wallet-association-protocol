import Foundation

public struct AssociationReplayCache: Sendable {
    private var recentRequestIds: [String: Set<String>] = [:]
    private let maxRequestIdsPerSession: Int
    private let clockSkewSeconds: TimeInterval

    public init(
        maxRequestIdsPerSession: Int = 128,
        clockSkewSeconds: TimeInterval = AssociationProtocol.rpcClockSkewSeconds
    ) {
        self.maxRequestIdsPerSession = maxRequestIdsPerSession
        self.clockSkewSeconds = clockSkewSeconds
    }

    public mutating func validate(_ request: AssociationRPCRequestPayload, sessionId: String, now: Date = Date()) throws {
        let age = abs(now.timeIntervalSince(request.issuedAt))
        guard age <= clockSkewSeconds else {
            throw WalletAssociationError.replayDetected
        }
        var ids = recentRequestIds[sessionId] ?? []
        guard !ids.contains(request.requestId) else {
            throw WalletAssociationError.replayDetected
        }
        ids.insert(request.requestId)
        if ids.count > maxRequestIdsPerSession {
            ids.remove(ids.first!)
        }
        recentRequestIds[sessionId] = ids
    }

    public mutating func removeAll() {
        recentRequestIds.removeAll()
    }
}
