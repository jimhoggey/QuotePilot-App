import AppKit
import Foundation
import QuotePilotCore

/// Brand → Settings' Let Claude use Quote Pilot, on the model's side: the HTTP answer, Settings'
/// line and button, and how Claude's tools change a quote. The tools are in `ClaudeTools`.
extension AppModel {
    func wireClaude() {
        claude.answer = { [weak self] request in
            self?.answerClaude(request) ?? ClaudeServer.Response(status: 503)
        }
    }

    /// One HTTP request from Claude: POST /mcp with the key, one JSON-RPC message in and one out.
    func answerClaude(_ request: ClaudeServer.Request) -> ClaudeServer.Response {
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else { return .init(status: 404) }
        // A web page sends an Origin and Claude Code doesn't, so a page in a browser can't get in.
        if let origin = request.headers["origin"], origin != "null" { return .init(status: 403) }
        guard request.headers["authorization"] == "Bearer \(claude.key)" else { return .init(status: 401) }
        guard request.method == "POST" else { return .init(status: 405, headers: ["Allow": "POST"]) }
        guard let reply = claudeMCP.reply(to: request.body) else { return .init(status: 202) }
        return .init(status: 200, body: reply)
    }

    /// Settings' line under the tick box.
    public var claudeLine: String {
        guard claude.isOn else { return "Off." }
        if let problem = claude.problem { return problem }
        guard claude.port != nil else { return "Starting…" }
        return "On, at \(claude.address)"
    }

    /// Copy Setup Command: the Terminal line that connects Claude Code, on the clipboard.
    public func copyClaudeSetupCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(claude.setupCommand, forType: .string)
        note("Copied the Claude setup command; paste it into Terminal")
    }

    /// Why Claude can't change `quote`, or nil when it can.
    func claudeEditProblem(_ quote: Quote) -> String? {
        if isLocked { return "Quote Pilot is locked until the Quote Pilot fee is paid, so nothing can be changed." }
        guard quote.stage == .draft else { return "\(quote.number) has been sent, so it can't be changed. Only draft quotes can." }
        return nil
    }

    /// Changes a draft quote in one save, notes it in Activity and the status bar, and shows it.
    func claudeEdit(_ quote: Quote, _ summary: String, _ edit: (inout Quote) throws -> Void) throws -> Quote {
        if let problem = claudeEditProblem(quote) { throw MCPError(problem) }
        var changed = quote
        try edit(&changed)
        let time = now()
        if let error = tryChange({ library in
            try library.update(changed)
            library.log("Claude \(summary) on \(quote.number)", number: quote.number, at: time)
        }) { throw error }
        note("Claude \(summary) on \(quote.number)")
        if openQuoteID != quote.id { openQuote(quote.id) }
        return library.quote(quote.id) ?? changed
    }
}
