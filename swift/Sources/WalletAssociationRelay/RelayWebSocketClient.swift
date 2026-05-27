import Foundation

protocol RelayWebSocketClient: Sendable {
    func connect(url: URL) async throws
    func send(_ string: String) async throws
    func receive() async throws -> String
    func close()
}

final class URLSessionRelayWebSocketClient: RelayWebSocketClient, @unchecked Sendable {
    private var task: URLSessionWebSocketTask?

    func connect(url: URL) async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func send(_ string: String) async throws {
        try await task?.send(.string(string))
    }

    func receive() async throws -> String {
        guard let task else {
            throw URLError(.notConnectedToInternet)
        }
        let message = try await task.receive()
        switch message {
        case .string(let string):
            return string
        case .data(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeRawData)
            }
            return string
        @unknown default:
            throw URLError(.cannotDecodeRawData)
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}
