import Foundation
import Network
import Observation

/// Brand → Settings' "Let Claude use Quote Pilot": an MCP server on this Mac that Claude Code
/// connects to with a secret key (`ClaudeTools` says what it can do). Off until the user ticks
/// the box; the box, the key and the port are kept in the app's preferences.
@MainActor @Observable
public final class ClaudeLink {
    nonisolated static let defaultPort: UInt16 = 47_210
    static let onKey = "ClaudeLinkOn"
    static let keyKey = "ClaudeLinkKey"

    /// The tick box. Ticking starts the server; unticking stops it.
    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            settings?.set(isOn, forKey: Self.onKey)
            isOn ? start() : stop()
        }
    }
    /// The port Claude connects to while the server is up; nil while it's off or couldn't start.
    public private(set) var port: UInt16?
    /// Why the server couldn't start, for Settings; nil otherwise.
    public private(set) var problem: String?

    /// The key Claude must send. Made once, at random, and kept.
    @ObservationIgnored let key: String
    @ObservationIgnored private let askedPort: UInt16
    @ObservationIgnored private let settings: UserDefaults?
    /// What a request gets (`AppModel.answerClaude`).
    @ObservationIgnored private let answer: @MainActor (ClaudeServer.Request) -> ClaudeServer.Response
    @ObservationIgnored private var server: ClaudeServer?

    init(settings: UserDefaults?, port: UInt16 = defaultPort,
         answer: @escaping @MainActor (ClaudeServer.Request) -> ClaudeServer.Response) {
        self.settings = settings
        askedPort = port
        self.answer = answer
        key = settings?.string(forKey: Self.keyKey).flatMap { $0.count >= 32 ? $0 : nil }
            ?? (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        settings?.set(key, forKey: Self.keyKey)
        isOn = settings?.bool(forKey: Self.onKey) ?? false
    }

    /// At launch: starts the server when the box was left ticked.
    func startIfOn() {
        if isOn, server == nil { start() }
    }

    /// Whether a request's Authorization header is "Bearer <key>". Every byte is compared, so how
    /// long the answer takes says nothing about how much of a guess was right.
    func accepts(_ authorization: String?) -> Bool {
        let given = Array((authorization ?? "").utf8), expected = Array("Bearer \(key)".utf8)
        return given.count == expected.count && zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// The address Claude Code connects to.
    var address: String { "http://127.0.0.1:\(port ?? askedPort)/mcp" }

    /// The one Terminal line that connects Claude Code, for every project (`--scope user`).
    public var setupCommand: String {
        "claude mcp add --scope user --transport http quote-pilot \(address) --header \"Authorization: Bearer \(key)\""
    }

    private func start() {
        problem = nil
        do {
            let server = try ClaudeServer(port: askedPort, handle: answer)
            self.server = server
            server.start { [weak self] result in Task { @MainActor in self?.started(result) } }
        } catch {
            started(.failure(error))
        }
    }

    private func started(_ result: Result<UInt16, Error>) {
        do {
            port = try result.get()
        } catch {
            stop()
            problem = (error as? NWError) == .posix(.EADDRINUSE)
                ? "Port \(askedPort) is in use by another app." : "Couldn't start: \(error.localizedDescription)"
        }
    }

    private func stop() {
        server?.stop()
        server = nil
        port = nil
        problem = nil
    }
}
