import Foundation

public struct AssociationReplayCache: Sendable {
    private var recentRequestIds: [String: OrderedRequestIds] = [:]
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
        let age = now.timeIntervalSince(request.issuedAt)
        guard age <= clockSkewSeconds, age >= -clockSkewSeconds else {
            throw WalletAssociationError.replayDetected
        }
        var ids = recentRequestIds[sessionId] ?? OrderedRequestIds()
        guard ids.insert(request.requestId) else {
            throw WalletAssociationError.replayDetected
        }
        ids.trim(to: maxRequestIdsPerSession)
        recentRequestIds[sessionId] = ids
    }

    public mutating func remove(sessionId: String) {
        recentRequestIds.removeValue(forKey: sessionId)
    }

    public mutating func removeAll() {
        recentRequestIds.removeAll()
    }
}

private struct OrderedRequestIds: Sendable {
    private var order: [String] = []
    private var ids: Set<String> = []

    mutating func insert(_ id: String) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.insert(id)
        order.append(id)
        return true
    }

    mutating func trim(to maxCount: Int) {
        guard maxCount > 0 else {
            order.removeAll()
            ids.removeAll()
            return
        }
        while order.count > maxCount {
            let removed = order.removeFirst()
            ids.remove(removed)
        }
    }
}
