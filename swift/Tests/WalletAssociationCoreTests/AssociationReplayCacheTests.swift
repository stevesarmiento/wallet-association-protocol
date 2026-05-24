import Foundation
@testable import WalletAssociationCore
import XCTest

final class AssociationReplayCacheTests: XCTestCase {
    func testRejectsDuplicateRequestId() throws {
        var cache = AssociationReplayCache(maxRequestIdsPerSession: 4, clockSkewSeconds: 60)
        let request = AssociationRPCRequestPayload.message(requestId: "duplicate", issuedAt: Date())

        try cache.validate(request, sessionId: "session")

        XCTAssertThrowsError(try cache.validate(request, sessionId: "session")) { error in
            XCTAssertEqual(error as? WalletAssociationError, .replayDetected)
        }
    }

    func testRejectsStaleAndFutureRequestsBeyondSkew() {
        var cache = AssociationReplayCache(maxRequestIdsPerSession: 4, clockSkewSeconds: 60)
        let now = Date(timeIntervalSince1970: 1000)

        XCTAssertThrowsError(try cache.validate(.message(requestId: "old", issuedAt: now.addingTimeInterval(-61)), sessionId: "session", now: now))
        XCTAssertThrowsError(try cache.validate(.message(requestId: "future", issuedAt: now.addingTimeInterval(61)), sessionId: "session", now: now))
    }

    func testEvictsOldestRequestIdsDeterministically() throws {
        var cache = AssociationReplayCache(maxRequestIdsPerSession: 2, clockSkewSeconds: 60)
        let now = Date()

        try cache.validate(.message(requestId: "one", issuedAt: now), sessionId: "session", now: now)
        try cache.validate(.message(requestId: "two", issuedAt: now), sessionId: "session", now: now)
        try cache.validate(.message(requestId: "three", issuedAt: now), sessionId: "session", now: now)

        XCTAssertNoThrow(try cache.validate(.message(requestId: "one", issuedAt: now), sessionId: "session", now: now))
        XCTAssertThrowsError(try cache.validate(.message(requestId: "three", issuedAt: now), sessionId: "session", now: now))
    }

    func testSameRequestIdAllowedAcrossSessionsAndRemoveClearsOneSession() throws {
        var cache = AssociationReplayCache(maxRequestIdsPerSession: 4, clockSkewSeconds: 60)
        let now = Date()

        try cache.validate(.message(requestId: "same", issuedAt: now), sessionId: "one", now: now)
        XCTAssertNoThrow(try cache.validate(.message(requestId: "same", issuedAt: now), sessionId: "two", now: now))

        cache.remove(sessionId: "one")
        XCTAssertNoThrow(try cache.validate(.message(requestId: "same", issuedAt: now), sessionId: "one", now: now))
        XCTAssertThrowsError(try cache.validate(.message(requestId: "same", issuedAt: now), sessionId: "two", now: now))
    }
}

private extension AssociationRPCRequestPayload {
    static func message(requestId: String, issuedAt: Date) -> AssociationRPCRequestPayload {
        AssociationRPCRequestPayload(
            requestId: requestId,
            issuedAt: issuedAt,
            sessionTokenBase64: Data(repeating: 7, count: 32).base64EncodedString(),
            method: "solana.signMessage",
            params: .signMessage(AssociationSignMessageParams(
                accountAddress: "account",
                messageBase64: Data("hello".utf8).base64EncodedString()
            ))
        )
    }
}
