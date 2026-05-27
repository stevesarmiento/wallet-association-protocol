import Foundation
import XCTest
@testable import WalletAssociationCore

final class AssociationConnectionURITests: XCTestCase {
    func testParsesRelayConnectionURI() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let value = AssociationConnectionURI(
            version: "2",
            transport: "relay",
            relayURL: URL(string: "ws://127.0.0.1:9000/v2/relay")!,
            roomId: "room",
            roomSecret: "secret",
            origin: "https://app.example",
            expiresAt: expiresAt
        )

        let parsed = try AssociationConnectionURI(uri: value.uriString(), now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(parsed.version, "2")
        XCTAssertEqual(parsed.transport, "relay")
        XCTAssertEqual(parsed.relayURL.absoluteString, "ws://127.0.0.1:9000/v2/relay")
        XCTAssertEqual(parsed.roomId, "room")
        XCTAssertEqual(parsed.roomSecret, "secret")
        XCTAssertEqual(parsed.origin, "https://app.example")
    }

    func testRejectsExpiredConnectionURI() throws {
        let uri = "wap://associate?version=2&transport=relay&relay=ws://127.0.0.1:9000/v2/relay&room=room&secret=secret&origin=https://app.example&expiresAt=2020-01-01T00:00:00Z"

        XCTAssertThrowsError(try AssociationConnectionURI(uri: uri, now: Date()))
    }
}
