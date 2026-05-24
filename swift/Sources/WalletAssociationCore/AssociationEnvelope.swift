import Foundation

public struct AssociationEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let keyId: String
    public let sealedBoxBase64: String

    public init(protocolVersion: String, keyId: String, sealedBoxBase64: String) {
        self.protocolVersion = protocolVersion
        self.keyId = keyId
        self.sealedBoxBase64 = sealedBoxBase64
    }
}

public struct AssociationErrorBody: Codable, Equatable, Sendable {
    public let error: AssociationErrorDetail

    public init(error: AssociationErrorDetail) {
        self.error = error
    }
}

public struct AssociationErrorDetail: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

