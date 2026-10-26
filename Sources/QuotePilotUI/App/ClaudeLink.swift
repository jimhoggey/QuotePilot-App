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
    @ObservationIgnored private var server: ClaudeServer?
    /// What a request gets; `AppModel` sets it to `answerClaude`.
    @ObservationIgnored var answer: (ClaudeServer.Request) -> ClaudeServer.Response = { _ in ClaudeServer.Response(status: 503) }

    init(settings: UserDefaults?, port: UInt16 = defaultPort) {
        self.settings = settings
        askedPort = port
        if let saved = settings?.string(forKey: Self.keyKey), saved.count >= 32 {
            key = saved
        } else {
            key = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
            settings?.set(key, forKey: Self.keyKey)
        }
        isOn = settings?.bool(forKey: Self.onKey) ?? false
    }

    static func live() -> ClaudeLink { ClaudeLink(settings: .standard) }

    /// At launch: starts the server when the box was left ticked.
    func startIfOn() {
        if isOn, server == nil { start() }
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
            let server = try ClaudeServer(port: askedPort) { [weak self] request in
                guard let link = self else { return ClaudeServer.Response(status: 503) }
                return await link.respond(request)
            }
            self.server = server
            server.start { [weak self] result in
                Task { @MainActor in self?.started(result) }
            }
        } catch {
            started(.failure(error))
        }
    }

    private func respond(_ request: ClaudeServer.Request) -> ClaudeServer.Response { answer(request) }

    private func started(_ result: Result<UInt16, Error>) {
        switch result {
        case .success(let port):
            self.port = port
        case .failure(let error):
            server?.stop()
            server = nil
            port = nil
            if case .posix(.EADDRINUSE)? = error as? NWError {
                problem = "Port \(askedPort) is in use by another app."
            } else {
                problem = "Couldn't start: \(error.localizedDescription)"
            }
        }
    }

    private func stop() {
        server?.stop()
        server = nil
        port = nil
        problem = nil
    }
}
