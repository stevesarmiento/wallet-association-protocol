import Foundation
import WalletAssociationCore

struct HTTPAssociationRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func expectedLength(in data: Data, maxRequestBytes: Int, maxBodyBytes: Int) throws -> Int? {
        guard data.count <= maxRequestBytes else {
            throw WalletAssociationError.requestTooLarge
        }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return nil
        }
        let bodyStart = headerRange.upperBound
        let headers = parseHeaders(from: headerText)
        let method = headerText.components(separatedBy: "\r\n").first?.split(separator: " ").first.map(String.init) ?? ""
        let contentLength = try parsedContentLength(method: method, headers: headers)
        guard contentLength <= maxBodyBytes, bodyStart + contentLength <= maxRequestBytes else {
            throw WalletAssociationError.requestTooLarge
        }
        return bodyStart + contentLength
    }

    init(data: Data, maxRequestBytes: Int, maxBodyBytes: Int) throws {
        guard data.count <= maxRequestBytes else {
            throw WalletAssociationError.requestTooLarge
        }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw WalletAssociationError.malformedRequest
        }
        let bodyStart = headerRange.upperBound
        let parsedHeaders = Self.parseHeaders(from: headerText)
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw WalletAssociationError.malformedRequest }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw WalletAssociationError.malformedRequest }
        self.method = String(parts[0])
        self.path = String(parts[1]).components(separatedBy: "?").first ?? String(parts[1])

        let contentLength = try Self.parsedContentLength(method: method, headers: parsedHeaders)
        guard contentLength <= maxBodyBytes, bodyStart + contentLength <= maxRequestBytes else {
            throw WalletAssociationError.requestTooLarge
        }
        if method == "POST" {
            guard Self.isJSONContentType(parsedHeaders["content-type"]) else {
                throw WalletAssociationError.malformedRequest
            }
        }
        guard data.count >= bodyStart + contentLength else {
            throw WalletAssociationError.malformedRequest
        }
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        self.headers = parsedHeaders
    }

    private static func parsedContentLength(method: String, headers: [String: String]) throws -> Int {
        guard method == "POST" else {
            return Int(headers["content-length"] ?? "0") ?? 0
        }
        guard let value = headers["content-length"],
              let length = Int(value),
              length >= 0
        else {
            throw WalletAssociationError.malformedRequest
        }
        return length
    }

    private static func isJSONContentType(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "application/json"
    }

    private static func parseHeaders(from headerText: String) -> [String: String] {
        var lines = headerText.components(separatedBy: "\r\n")
        if !lines.isEmpty {
            lines.removeFirst()
        }
        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headers
    }
}
