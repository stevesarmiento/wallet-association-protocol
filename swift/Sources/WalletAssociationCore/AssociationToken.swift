import Foundation

public enum AssociationToken {
    public static let byteCount = 32

    public static func validate(_ token: Data) throws {
        guard token.count == byteCount else {
            throw WalletAssociationError.sessionTokenInvalid
        }
    }

    public static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
