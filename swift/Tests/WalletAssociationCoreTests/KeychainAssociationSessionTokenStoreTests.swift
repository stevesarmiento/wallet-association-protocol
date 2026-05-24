import Foundation
@testable import WalletAssociationCore
import XCTest

final class KeychainAssociationSessionTokenStoreTests: XCTestCase {
    func testStoreLoadDeleteAndDeleteAll() throws {
        let store = KeychainAssociationSessionTokenStore(service: "com.walletassociation.tests.\(UUID().uuidString)")
        let token = Data(repeating: 7, count: 32)
        let otherToken = Data(repeating: 8, count: 32)

        try store.store(sessionId: "one", token: token)
        try store.store(sessionId: "two", token: otherToken)

        XCTAssertEqual(try store.load(sessionId: "one"), token)
        XCTAssertEqual(try store.load(sessionId: "two"), otherToken)

        try store.delete(sessionId: "one")
        XCTAssertThrowsError(try store.load(sessionId: "one"))

        try store.deleteAll(sessionIds: ["two"])
        XCTAssertThrowsError(try store.load(sessionId: "two"))
    }
}
