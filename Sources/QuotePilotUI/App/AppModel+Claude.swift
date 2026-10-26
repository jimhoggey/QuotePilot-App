import AppKit
import Foundation
import QuotePilotCore

/// What a Claude tool refuses with: the words Claude reads back.
struct ClaudeToolError: Error {
    let text: String
    init(_ text: String) { self.text = text }
}

/// Claude's MCP tools (the user, 26 Oct 2026). Claude can see what's open and fill in draft quotes:
/// lines, title, Work summary and the Included / Not included lists. It can't send, record
/// payments, delete documents or change anything sent; each change goes in Activity as "Claude: …".
extension AppModel {
    // MARK: The MCP conversation

    static let mcpVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static let claudeInstructions = """
        Quote Pilot is the user's Mac app for quotes and invoices, in Australian dollars. Call \
        get_current_view first to see what the user is looking at. You can start draft quotes and fill \
        them in: lines, title, Work summary and the Included / Not included lists. You can't send \
        anything, record payments or delete documents; the user does those in Quote Pilot. Only draft \
        quotes can be changed. Keep line titles short (a few words) and put longer wording in detail. \
        Rates are dollars per unit before GST; for work in hours, leave rate out to use the user's \
        hourly rate. Line IDs (01, 02, …) renumber when a line is removed, so read them from the latest \
        result. When you're done, ask the user to check the quote in Quote Pilot.
        """

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
        guard request.method == "POST" else {
            return .init(status: request.method.isEmpty ? 400 : 405, headers: ["Allow": "POST"])
        }
        guard let reply = answerMCP(request.body) else { return .init(status: 202) }
        return .init(status: 200, body: reply)
    }

    /// A JSON-RPC message in, its answer out; nil for a notification, which gets none.
    func answerMCP(_ body: Data) -> Data? {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = message["method"] as? String
        else { return Self.rpc(id: NSNull(), error: -32700, "Parse error: send one JSON-RPC request") }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return Self.rpc(id: id, result: [
                "protocolVersion": Self.mcpVersions.contains(asked) ? asked : Self.mcpVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "quote-pilot", "version": AppVersion.current],
                "instructions": Self.claudeInstructions,
            ])
        case "ping":
            return Self.rpc(id: id, result: [String: Any]())
        case "tools/list":
            return Self.rpc(id: id, result: ["tools": Self.claudeTools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            return Self.rpc(id: id, result: callClaudeTool(name, params["arguments"] as? [String: Any] ?? [:]))
        default:
            return Self.rpc(id: id, error: -32601, "Method not found: \(method)")
        }
    }

    static func rpc(id: Any, result: Any) -> Data? {
        json(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func rpc(id: Any, error code: Int, _ text: String) -> Data? {
        json(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]])
    }

    static func json(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Settings

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

    // MARK: The tools

    static let quoteArgument: [String: Any] = [
        "type": "string",
        "description": "A quote number, like Q-0012. Leave it out for the quote open in Quote Pilot.",
    ]

    static let lineProperties: [String: Any] = [
        "title": ["type": "string", "description": "A few words, like \"Contact form\"."],
        "detail": ["type": "string", "description": "Longer wording, shown under the title."],
        "quantity": ["type": "number", "description": "How many hours, days or units; at most two decimal places. Default 1."],
        "unit": ["type": "string", "enum": ["hours", "days", "units"]],
        "rate": ["type": "number", "description": "Dollars per unit, before GST. Leave it out for hours to use the hourly rate."],
    ]

    static let claudeTools: [[String: Any]] = [
        tool("get_current_view", "What the user is looking at in Quote Pilot: the section, the open quote with its lines and totals, the hourly rate."),
        tool("list_quotes", "Every quote, newest first: number, client, title, stage and total."),
        tool("list_clients", "Every client's name."),
        tool("open_quote", "Opens a quote in Quote Pilot so the user sees it.",
             ["quote": ["type": "string", "description": "A quote number, like Q-0012."]], required: ["quote"]),
        tool("new_quote", "Starts a draft quote and opens it.",
             ["client": ["type": "string", "description": "The client's name, as list_clients gives it. Optional."],
              "title": ["type": "string", "description": "What the quote is for. Optional."]]),
        tool("add_quote_lines", "Adds lines to the end of a draft quote.",
             ["quote": quoteArgument,
              "lines": ["type": "array", "items": ["type": "object", "properties": lineProperties, "required": ["title"]]]],
             required: ["lines"]),
        tool("update_quote_line", "Changes one line of a draft quote; only the fields given change.",
             lineProperties.merging(["quote": quoteArgument,
                                     "line": ["type": "string", "description": "The line's ID, like 03."]]) { $1 },
             required: ["line"]),
        tool("remove_quote_lines", "Removes lines from a draft quote. The lines after them renumber.",
             ["quote": quoteArgument,
              "lines": ["type": "array", "items": ["type": "string"], "description": "Line IDs, like [\"03\", \"04\"]."]],
             required: ["lines"]),
        tool("set_quote_text", "Sets a draft quote's title, Work summary, or Included / Not included lists. Only the fields given change.",
             ["quote": quoteArgument,
              "title": ["type": "string"],
              "summary": ["type": "string", "description": "The Work summary. Lines starting with \"-\" print as dot points."],
              "included": ["type": "array", "items": ["type": "string"], "description": "One item each. An empty list removes them."],
              "not_included": ["type": "array", "items": ["type": "string"], "description": "One item each. An empty list removes them."]]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:],
                             required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    /// Runs one tool. A refusal comes back as text with isError, so Claude can read why.
    func callClaudeTool(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        do {
            let result: Any
            switch name {
            case "get_current_view": result = claudeView()
            case "list_quotes": result = library.quotes.sorted { ($0.issued, $0.number) > ($1.issued, $1.number) }.map(claudeQuoteSummary)
            case "list_clients": result = library.clients.map { ["name": $0.name] }
            case "open_quote": result = claudeQuote(try claudeOpen(arguments))
            case "new_quote": result = claudeQuote(try claudeNewQuote(arguments))
            case "add_quote_lines": result = claudeQuote(try claudeAddLines(arguments))
            case "update_quote_line": result = claudeQuote(try claudeUpdateLine(arguments))
            case "remove_quote_lines": result = claudeQuote(try claudeRemoveLines(arguments))
            case "set_quote_text": result = claudeQuote(try claudeSetText(arguments))
            default: throw ClaudeToolError("There's no tool called \(name).")
            }
            track(.claudeTool, ["tool": name])
            let text = Self.json(result).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return ["content": [["type": "text", "text": text]], "isError": false]
        } catch {
            let text = (error as? ClaudeToolError)?.text ?? error.localizedDescription
            return ["content": [["type": "text", "text": text]], "isError": true]
        }
    }

    // MARK: Reading

    func claudeView() -> [String: Any] {
        let rate = library.brand.hourlyRate.flatMap { $0 > .zero ? $0 : nil }
        var view: [String: Any] = [
            "section": "\(section)",
            "locked": isLocked,
            "hourly_rate": rate.map { Self.dollars($0) as Any } ?? NSNull(),
            "gst_registered": library.brand.gstRegistered,
        ]
        if let id = openQuoteID, let quote = library.quote(id) {
            view["open_quote"] = claudeQuote(quote)
        } else if section == .quotes, let id = selectedQuoteID, let quote = library.quote(id) {
            view["selected_quote"] = claudeQuote(quote)
        }
        if let id = openInvoiceID, let invoice = library.invoice(id) {
            view["open_invoice"] = ["number": invoice.number, "client": clientName(invoice.clientID), "stage": "\(invoice.stage)"]
        }
        if section == .clients, let id = selectedClientID, let client = library.client(id) {
            view["selected_client"] = client.name
        }
        return view
    }

    func claudeQuote(_ quote: Quote) -> [String: Any] {
        [
            "number": quote.number,
            "client": clientName(quote.clientID),
            "title": quote.title,
            "stage": quote.stage.rawValue,
            "editable": claudeEditProblem(quote) == nil,
            "plan": quote.plan == .fiftyFifty ? "50% deposit, 50% on completion" : "full amount",
            "summary": quote.summary,
            "included": quote.included,
            "not_included": quote.notIncluded,
            "lines": quote.lines.map { line -> [String: Any] in
                ["line": line.code, "title": line.title, "detail": line.detail, "quantity": Self.number(line.quantity),
                 "unit": line.unit.rawValue, "rate": Self.dollars(line.rate), "amount": Self.dollars(line.amount)]
            },
            "subtotal": Self.dollars(quote.totals.subtotal),
            "gst": Self.dollars(quote.totals.gst),
            "total": Self.dollars(quote.totals.total),
        ]
    }

    func claudeQuoteSummary(_ quote: Quote) -> [String: Any] {
        ["number": quote.number, "client": clientName(quote.clientID), "title": quote.title,
         "stage": quote.stage.rawValue, "issued": quote.issued.iso, "total": Self.dollars(quote.totals.total)]
    }

    private func clientName(_ id: UUID?) -> String { id.flatMap { library.client($0)?.name } ?? "" }

    static func dollars(_ amount: Money) -> Double { Double(amount.cents) / 100 }
    static func number(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

    // MARK: Changing

    /// The quote named by `quote`, or else the one open (or selected in the Quotes list).
    func claudeTarget(_ arguments: [String: Any]) throws -> Quote {
        if let number = (arguments["quote"] as? String)?.trimmingCharacters(in: .whitespaces), !number.isEmpty {
            guard let quote = library.quote(number: number) else {
                throw ClaudeToolError("There's no quote \(number). list_quotes shows them all.")
            }
            return quote
        }
        if let id = openQuoteID ?? (section == .quotes ? selectedQuoteID : nil), let quote = library.quote(id) {
            return quote
        }
        throw ClaudeToolError("No quote is open in Quote Pilot. Pass a quote number, or start one with new_quote.")
    }

    /// Why Claude can't change `quote`, or nil when it can.
    func claudeEditProblem(_ quote: Quote) -> String? {
        if isLocked { return "Quote Pilot is locked until the Quote Pilot fee is paid, so nothing can be changed." }
        guard quote.stage == .draft else { return "\(quote.number) has been sent, so it can't be changed. Only draft quotes can." }
        return nil
    }

    /// Changes a draft quote in one save, notes it in Activity and the status bar, and shows it.
    func claudeEdit(_ quote: Quote, _ summary: String, _ edit: (inout Quote) throws -> Void) throws -> Quote {
        if let problem = claudeEditProblem(quote) { throw ClaudeToolError(problem) }
        var changed = quote
        try edit(&changed)
        let time = now()
        if let error = tryChange({ library in
            try library.update(changed)
            library.log("Claude \(summary) on \(quote.number)", number: quote.number, at: time)
        }) {
            throw ClaudeToolError(error.localizedDescription)
        }
        note("Claude \(summary) on \(quote.number)")
        if openQuoteID != quote.id { openQuote(quote.id) }
        return library.quote(quote.id) ?? changed
    }

    func claudeOpen(_ arguments: [String: Any]) throws -> Quote {
        guard arguments["quote"] is String else { throw ClaudeToolError("Pass quote: a quote number like Q-0012.") }
        let quote = try claudeTarget(arguments)
        openQuote(quote.id)
        return quote
    }

    func claudeNewQuote(_ arguments: [String: Any]) throws -> Quote {
        if let lockedError { throw ClaudeToolError(lockedError.text) }
        var clientID: UUID?
        if let name = (arguments["client"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            let clients = library.clients
            let exact = clients.filter { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
            let partial = clients.filter { $0.name.localizedCaseInsensitiveContains(name) }
            guard let client = exact.first ?? (partial.count == 1 ? partial.first : nil) else {
                throw ClaudeToolError("No single client matches \"\(name)\". The clients are: \(clients.map(\.name).joined(separator: ", ")). Leave client out to start the quote without one.")
            }
            clientID = client.id
        }
        let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var created: UUID?
        if let error = tryChange({ library in
            var quote = library.newQuote(on: today, clientID: clientID)
            if !title.isEmpty {
                quote.title = title
                try library.update(quote)
            }
            created = quote.id
        }) {
            throw ClaudeToolError(error.localizedDescription)
        }
        guard let created, let quote = library.quote(created) else { throw ClaudeToolError("The quote wasn't saved.") }
        note("Claude started \(quote.number)")
        openQuote(quote.id)
        return quote
    }

    func claudeAddLines(_ arguments: [String: Any]) throws -> Quote {
        let quote = try claudeTarget(arguments)
        guard let items = arguments["lines"] as? [[String: Any]], !items.isEmpty else {
            throw ClaudeToolError("Pass lines: a list of {title, detail, quantity, unit, rate}.")
        }
        guard items.count <= 200 else { throw ClaudeToolError("Add at most 200 lines at a time.") }
        let hourly = library.brand.hourlyRate
        let lines = try items.map { item -> LineItem in
            var fields = item
            if fields["unit"] == nil, fields["rate"] == nil {
                fields["unit"] = LineItem.startingUnit(hourlyRate: hourly).rawValue
            }
            return try claudeLine(fields, to: LineItem(title: "", rate: .zero)).withHourlyRate(hourly, after: nil)
        }
        let count = lines.count
        return try claudeEdit(quote, "added \(count) line\(count == 1 ? "" : "s")") { quote in
            lines.forEach { quote.addLine($0) }
        }
    }

    func claudeUpdateLine(_ arguments: [String: Any]) throws -> Quote {
        let quote = try claudeTarget(arguments)
        guard let code = Self.lineCode(arguments["line"]),
              let index = quote.lines.firstIndex(where: { $0.code == code })
        else {
            throw ClaudeToolError("\(quote.number) has no line \(arguments["line"] ?? ""). Its lines are \(quote.lines.map(\.code).joined(separator: ", ")).")
        }
        let previous = quote.lines[index]
        let line = try claudeLine(arguments, to: previous).withHourlyRate(library.brand.hourlyRate, after: previous)
        return try claudeEdit(quote, "changed line \(code)") { $0.lines[index] = line }
    }

    func claudeRemoveLines(_ arguments: [String: Any]) throws -> Quote {
        let quote = try claudeTarget(arguments)
        let codes = (arguments["lines"] as? [Any] ?? []).compactMap(Self.lineCode)
        guard !codes.isEmpty else { throw ClaudeToolError("Pass lines: the IDs to remove, like [\"03\"].") }
        let missing = codes.filter { code in !quote.lines.contains { $0.code == code } }
        guard missing.isEmpty else {
            throw ClaudeToolError("\(quote.number) has no line \(missing.joined(separator: ", ")). Its lines are \(quote.lines.map(\.code).joined(separator: ", ")).")
        }
        return try claudeEdit(quote, "removed \(codes.count) line\(codes.count == 1 ? "" : "s")") { quote in
            quote.lines.removeAll { codes.contains($0.code) }
        }
    }

    func claudeSetText(_ arguments: [String: Any]) throws -> Quote {
        let quote = try claudeTarget(arguments)
        let title = arguments["title"] as? String
        let summary = arguments["summary"] as? String
        let included = arguments["included"] as? [String]
        let notIncluded = arguments["not_included"] as? [String]
        let names = [(title, "title"), (summary, "Work summary")].compactMap { $0.0 == nil ? nil : $0.1 }
            + [(included, "Included list"), (notIncluded, "Not included list")].compactMap { $0.0 == nil ? nil : $0.1 }
        guard !names.isEmpty else { throw ClaudeToolError("Pass at least one of title, summary, included or not_included.") }
        let items = { (list: [String]) in
            list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return try claudeEdit(quote, "set the \(names.joined(separator: ", "))") { quote in
            if let title { quote.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let summary { quote.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let included { quote.included = items(included) }
            if let notIncluded { quote.notIncluded = items(notIncluded) }
        }
    }

    /// `line` with the fields Claude gave: title, detail, quantity, unit and rate.
    func claudeLine(_ fields: [String: Any], to line: LineItem) throws -> LineItem {
        var line = line
        if let title = fields["title"] as? String { line.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let detail = fields["detail"] as? String { line.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let unit = fields["unit"] as? String {
            guard let parsed = Unit(rawValue: unit.lowercased()) else { throw ClaudeToolError("unit must be hours, days or units.") }
            line.unit = parsed
        }
        if let quantity = fields["quantity"] {
            guard let value = Self.text(quantity).flatMap(FieldParser.quantity) else {
                throw ClaudeToolError("quantity must be a number from 0, with at most two decimal places.")
            }
            line.quantity = value
        }
        if let rate = fields["rate"] {
            guard let value = Self.text(rate).flatMap(FieldParser.money) else {
                throw ClaudeToolError("rate must be a dollar amount, like 450 or 89.50.")
            }
            line.rate = value
        }
        guard !line.title.isEmpty else { throw ClaudeToolError("Every line needs a title.") }
        return line
    }

    /// A number or text from JSON, as text for the field parsers.
    static func text(_ value: Any) -> String? {
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String
    }

    /// "3", 3 or "03" → "03".
    static func lineCode(_ value: Any?) -> String? {
        if let number = value as? NSNumber { return String(format: "%02d", number.intValue) }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let number = Int(text) { return String(format: "%02d", number) }
        return text
    }
}
