import Foundation

public protocol AssociationBridgeDelegate: AnyObject, Sendable {
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

    func associationRotateSessionToken(
        _ request: AssociationSessionRotationRequest,
        session: AssociationSessionContext
    ) async throws -> AssociationSessionRotationResponse
}

public extension AssociationBridgeDelegate {
    func associationRotateSessionToken(
        _ request: AssociationSessionRotationRequest,
        session: AssociationSessionContext
    ) async throws -> AssociationSessionRotationResponse {
        throw WalletAssociationError.unsupportedMethod("wallet.session.rotate")
    }
}
