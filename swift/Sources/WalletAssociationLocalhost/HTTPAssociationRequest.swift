import Foundation
import WalletAssociationCore

struct HTTPAssociationRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func expectedLength(in data: Data) -> Int? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return nil
        }
        let bodyStart = headerRange.upperBound
        let headers = parseHeaders(from: headerText)
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        return bodyStart + contentLength
    }

    init(data: Data) throws {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw WalletAssociationError.malformedRequest
        }
        let bodyStart = headerRange.upperBound
        let parsedHeaders = Self.parseHeaders(from: headerText)
        let contentLength = Int(parsedHeaders["content-length"] ?? "") ?? 0
        guard data.count >= bodyStart + contentLength else {
            throw WalletAssociationError.malformedRequest
        }
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw WalletAssociationError.malformedRequest }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw WalletAssociationError.malformedRequest }
        self.method = String(parts[0])
        self.path = String(parts[1]).components(separatedBy: "?").first ?? String(parts[1])
        self.headers = parsedHeaders
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

