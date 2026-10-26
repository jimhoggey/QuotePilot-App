import Foundation
import Network

/// A tiny HTTP server for Claude's MCP connection, on this Mac only: it listens on the loopback
/// interface, so nothing on the network can reach it. One request per connection, then it closes;
/// a connection still open after `timeout` (10 seconds) is closed anyway, so a client that sends
/// nothing, or never finishes, can't hold one. What a request gets is up to `handle`; the server only
/// reads and writes HTTP.
final class ClaudeServer: @unchecked Sendable {
    struct Request {
        var method = "", path = ""
        /// Header names in lower case.
        var headers: [String: String] = [:]
        var body = Data()
    }

    struct Response {
        var status: Int
        var body = Data()
        var headers: [String: String] = [:]
    }

    /// Requests bigger than this are refused (413): an MCP message is a few kilobytes.
    static let maxRequest = 1_000_000
    private static let reasons = [200: "OK", 202: "Accepted", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                                  405: "Method Not Allowed", 413: "Payload Too Large", 503: "Service Unavailable"]

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.fynnprojects.quotepilot.claude")
    private let timeout: TimeInterval
    private let handle: @Sendable (Request) async -> Response

    /// Port 0 picks a free one (the tests). Bound to 127.0.0.1, so macOS's firewall never asks and
    /// nothing else on the network can connect.
    init(port: UInt16, timeout: TimeInterval = 10, handle: @escaping @Sendable (Request) async -> Response) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        listener = try NWListener(using: parameters)
        self.timeout = timeout
        self.handle = handle
    }

    /// Starts listening. `ready` is called once, on the server's queue: with the port, or with the
    /// error when it can't (another app has the port).
    func start(ready: @escaping @Sendable (Result<UInt16, Error>) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                ready(.success(self?.listener.port?.rawValue ?? 0))
            case .failed(let error):
                ready(.failure(error))
                self?.listener.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak connection] in connection?.cancel() }
            receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.cancel()
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            let buffer = buffer + (data ?? Data())
            if buffer.count > Self.maxRequest {
                send(Response(status: 413), on: connection)
            } else if let request = Self.parse(buffer) {
                Task { self.send(await self.handle(request), on: connection) }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(connection, buffer: buffer)
            }
        }
    }

    /// The request in `data` once its headers and all of its body are in; nil until then. A first
    /// line that isn't "METHOD /path …" leaves the method and path empty, for a 404.
    static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        var lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ").map(String.init)
        var request = first.count < 2 ? Request() : Request(method: first[0], path: first[1])
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            request.headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = data[end.upperBound...], length = max(Int(request.headers["content-length"] ?? "") ?? 0, 0)
        guard body.count >= length else { return nil }
        request.body = Data(body.prefix(length))
        return request
    }

    private func send(_ response: Response, on connection: NWConnection) {
        var headers = response.headers.merging(["Content-Length": "\(response.body.count)", "Connection": "close"]) { $1 }
        if !response.body.isEmpty, headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        let head = "HTTP/1.1 \(response.status) \(Self.reasons[response.status] ?? "")\r\n"
            + headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
