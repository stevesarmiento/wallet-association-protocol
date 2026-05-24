import Foundation
import WalletAssociationCore

public protocol LocalAssociationBridgeDelegate: AnyObject, Sendable {
    func associationApprove(
        _ request: AssociationRequestPayload,
        context: AssociationHandshakeContext
    ) async throws -> AssociationResponsePayload

    func associationSessionToken(
        sessionId: String,
        verifiedOrigin: String
    ) async throws -> AssociationSessionToken

    func associationRPC(
        _ request: AssociationRPCRequestPayload,
        session: AssociationSessionContext
    ) async throws -> AssociationRPCResponsePayload
}

