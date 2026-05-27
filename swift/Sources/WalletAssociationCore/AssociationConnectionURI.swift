import Foundation

public struct AssociationConnectionURI: Equatable, Sendable {
    public let version: String
    public let transport: String
    public let relayURL: URL
    public let roomId: String
    public let roomSecret: String
    public let origin: String
    public let expiresAt: Date

    public init(
        version: String,
        transport: String,
        relayURL: URL,
        roomId: String,
        roomSecret: String,
        origin: String,
        expiresAt: Date
    ) {
        self.version = version
        self.transport = transport
        self.relayURL = relayURL
        self.roomId = roomId
        self.roomSecret = roomSecret
        self.origin = origin
        self.expiresAt = expiresAt
    }

    public init(uri: String, now: Date = Date()) throws {
        guard let components = URLComponents(string: uri),
              components.scheme == "wap",
              components.host == "associate"
        else {
            throw WalletAssociationError.malformedRequest
        }

        func value(_ name: String) throws -> String {
            guard let value = components.queryItems?.first(where: { $0.name == name })?.value,
                  !value.isEmpty
            else {
                throw WalletAssociationError.malformedRequest
            }
            return value
        }

        let version = try value("version")
        let transport = try value("transport")
        guard version == AssociationProtocol.version, transport == "relay" else {
            throw WalletAssociationError.unsupportedProtocol(version)
        }
        guard let relayURL = URL(string: try value("relay")) else {
            throw WalletAssociationError.malformedRequest
        }
        let expiresAt = try AssociationConnectionURI.date(from: value("expiresAt"))
        guard expiresAt > now else {
            throw WalletAssociationError.sessionExpired
        }

        self.init(
            version: version,
            transport: transport,
            relayURL: relayURL,
            roomId: try value("room"),
            roomSecret: try value("secret"),
            origin: try value("origin"),
            expiresAt: expiresAt
        )
    }

    public func uriString() -> String {
        var components = URLComponents()
        components.scheme = "wap"
        components.host = "associate"
        components.queryItems = [
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "transport", value: transport),
            URLQueryItem(name: "relay", value: relayURL.absoluteString),
            URLQueryItem(name: "room", value: roomId),
            URLQueryItem(name: "secret", value: roomSecret),
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "expiresAt", value: AssociationConnectionURI.string(from: expiresAt))
        ]
        return components.url?.absoluteString ?? ""
    }

    private static func date(from value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw WalletAssociationError.malformedRequest
        }
        return date
    }

    private static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
