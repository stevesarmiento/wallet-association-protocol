import Foundation
@testable import WalletAssociationCore
import XCTest

final class AssociationTokenTests: XCTestCase {
    func testValidatesExactlyThirtyTwoBytes() {
        XCTAssertNoThrow(try AssociationToken.validate(Data(repeating: 1, count: 32)))
        XCTAssertThrowsError(try AssociationToken.validate(Data()))
        XCTAssertThrowsError(try AssociationToken.validate(Data(repeating: 1, count: 31)))
        XCTAssertThrowsError(try AssociationToken.validate(Data(repeating: 1, count: 33)))
    }

    func testConstantTimeEqualsRequiresEqualBytesAndLength() {
        let token = Data(repeating: 7, count: 32)
        XCTAssertTrue(AssociationToken.constantTimeEquals(token, token))
        XCTAssertFalse(AssociationToken.constantTimeEquals(token, Data(repeating: 8, count: 32)))
        XCTAssertFalse(AssociationToken.constantTimeEquals(token, Data(repeating: 7, count: 31)))
    }
}
