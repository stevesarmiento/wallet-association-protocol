import Foundation
@testable import WalletAssociationCore
import XCTest

final class AssociationAuthorizationRegistryTests: XCTestCase {
    func testUpsertRequireRecordAndRevokeSession() throws {
        let origin = "https://app.example"
        let now = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        var authorizations: [AssociationOriginAuthorization] = []
        let session = AssociationSessionAuthorization(
            sessionId: "session",
            dappPublicKeyBase64: "key",
            appName: "Example",
            transport: "localhost",
            firstConnectedAt: now,
            lastConnectedAt: now,
            expiresAt: later,
            signingPolicy: .prompt
        )

        AssociationAuthorizationRegistry.upsertSession(
            origin: origin,
            metadata: AssociationRequestMetadata(origin: origin, appName: "Example"),
            session: session,
            in: &authorizations,
            now: now
        )

        XCTAssertEqual(authorizations.first?.displayName, "Example")
        XCTAssertEqual(try AssociationAuthorizationRegistry.requireSession(origin: origin, sessionId: "session", in: authorizations), session)

        AssociationAuthorizationRegistry.recordUse(origin: origin, sessionId: "session", in: &authorizations, now: later)
        XCTAssertEqual(authorizations.first?.lastConnectedAt, later)
        XCTAssertEqual(authorizations.first?.sessions.first?.lastConnectedAt, later)

        let revoked = AssociationAuthorizationRegistry.revokeSession(origin: origin, sessionId: "session", in: &authorizations)
        XCTAssertEqual(revoked, ["session"])
        XCTAssertTrue(authorizations.isEmpty)
    }

    func testRevokeOriginReturnsAllSessionIds() {
        var authorizations = [
            AssociationOriginAuthorization(origin: "https://app.example", sessions: [
                AssociationSessionAuthorization(sessionId: "one", dappPublicKeyBase64: "key", expiresAt: Date()),
                AssociationSessionAuthorization(sessionId: "two", dappPublicKeyBase64: "key", expiresAt: Date())
            ])
        ]

        XCTAssertEqual(
            AssociationAuthorizationRegistry.revokeOrigin(origin: "https://app.example", in: &authorizations),
            ["one", "two"]
        )
        XCTAssertTrue(authorizations.isEmpty)
    }
}

