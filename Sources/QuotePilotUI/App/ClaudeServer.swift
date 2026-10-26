import Foundation
import Network

/// A tiny HTTP server for Claude's MCP connection, on this Mac only: it listens on the loopback
/// interface, so nothing on the network can reach it. One request per connection, then it closes.
/// What a request gets is up to `handle`; the server only reads and writes HTTP.
final class ClaudeServer: @unchecked Sendable {
    struct Request {
        var method: String
        var path: String
        /// Header names in lower case.
        var headers: [String: String]
        var body: Data
    }

    struct Response {
        var status: Int
        var body = Data()
        var headers: [String: String] = [:]
    }

    /// Requests bigger than this are refused (413): an MCP message is a few kilobytes.
    static let maxRequest = 1_000_000

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.fynnprojects.quotepilot.claude")
    private let handle: @Sendable (Request) async -> Response

    /// Port 0 picks a free one (the tests). Bound to 127.0.0.1, so macOS's firewall never asks and
    /// nothing else on the network can connect.
    init(port: UInt16, handle: @escaping @Sendable (Request) async -> Response) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        listener = try NWListener(using: parameters)
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
            var buffer = buffer
            if let data { buffer.append(data) }
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
    /// line that isn't "METHOD /path …" comes back with an empty method, for a 400.
    static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return Request(method: "", path: "", headers: [:], body: Data()) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = max(Int(headers["content-length"] ?? "") ?? 0, 0)
        guard data.distance(from: end.upperBound, to: data.endIndex) >= length else { return nil }
        let body = Data(data[end.upperBound..<data.index(end.upperBound, offsetBy: length)])
        return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: body)
    }

    private func send(_ response: Response, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        if !response.body.isEmpty, headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Service Unavailable"
        }
    }
}
