import Foundation
import WalletAssociationCore

enum HTTPAssociationResponse {
    static func success<T: Encodable>(
        status: Int,
        encodable: T,
        encoder: JSONEncoder,
        request: HTTPAssociationRequest?
    ) throws -> Data {
        response(status: status, body: try encoder.encode(encodable), request: request)
    }

    static func response(status: Int, body: Data, request: HTTPAssociationRequest?) -> Data {
        let reason = reasonPhrase(for: status)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if status != 204 {
            head += "Content-Type: application/json\r\n"
        }
        if let origin = request?.headers["origin"], LocalhostCORS.isValidBrowserOrigin(origin) {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Vary: Origin\r\n"
            head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func error(status: Int, code: String, message: String, encoder: JSONEncoder, request: HTTPAssociationRequest?) -> Data {
        let body = AssociationErrorBody(error: AssociationErrorDetail(code: code, message: message))
        return (try? success(status: status, encodable: body, encoder: encoder, request: request))
            ?? response(status: status, body: Data(), request: request)
    }

    static func bridgeError(_ error: Error, encoder: JSONEncoder, request: HTTPAssociationRequest?) -> Data {
        if let associationError = error as? WalletAssociationError {
            switch associationError {
            case .userRejected:
                return self.error(status: 403, code: "user_rejected", message: "user rejected", encoder: encoder, request: request)
            case .invalidOrigin:
                return self.error(status: 400, code: "invalid_origin", message: associationError.localizedDescription, encoder: encoder, request: request)
            case .unsupportedProtocol:
                return self.error(status: 400, code: "unsupported_protocol", message: associationError.localizedDescription, encoder: encoder, request: request)
            case .sessionNotFound, .sessionExpired, .sessionTokenInvalid, .replayDetected:
                return self.error(status: 403, code: "session_invalid", message: associationError.localizedDescription, encoder: encoder, request: request)
            case .unsupportedMethod:
                return self.error(status: 400, code: "unsupported_method", message: associationError.localizedDescription, encoder: encoder, request: request)
            case .invalidHandshake, .invalidEnvelope, .malformedRequest:
                return self.error(status: 400, code: "malformed_request", message: associationError.localizedDescription, encoder: encoder, request: request)
            case .unavailable:
                return self.error(status: 503, code: "bridge_unavailable", message: associationError.localizedDescription, encoder: encoder, request: request)
            default:
                return self.error(status: 400, code: "bridge_error", message: associationError.localizedDescription, encoder: encoder, request: request)
            }
        }
        return self.error(status: 400, code: "malformed_request", message: error.localizedDescription, encoder: encoder, request: request)
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}

