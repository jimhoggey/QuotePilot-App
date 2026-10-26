import Foundation
import QuotePilotCore

/// Claude's tools (the user, 26 Oct 2026). Claude can see what's open and fill in draft quotes:
/// lines, title, Work summary, the Included / Not included lists, terms and payment plan. It can't
/// send, record payments, delete documents or change anything sent; each change goes in Activity as
/// "Claude …".
extension AppModel {
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

    /// Quote Pilot as Claude's MCP server. Each tool's arguments sit next to what it does.
    var claudeMCP: MCPServer {
        let quote = Self.text("A quote number, like Q-0012. Leave it out for the quote open in Quote Pilot.")
        let items: [String: Any] = ["type": "array", "items": ["type": "string"], "description": "One item each. An empty list removes them."]
        let lineFields: [String: Any] = [
            "title": Self.text("A few words, like \"Contact form\"."),
            "detail": Self.text("Longer wording, shown under the title."),
            "quantity": ["type": "number", "description": "How many hours, days or units; at most two decimal places. Default 1."],
            "unit": ["type": "string", "enum": ["hours", "days", "units"]],
            "rate": ["type": "number", "description": "Dollars per unit, before GST. Leave it out for hours to use the hourly rate."],
        ]
        return MCPServer(name: "quote-pilot", version: AppVersion.current, instructions: Self.claudeInstructions, tools: [
            tool("get_current_view", "What the user is looking at in Quote Pilot: the section, the open quote with its lines and totals, the hourly rate.",
                 readOnly: true) { [self] _ in claudeView },
            tool("list_quotes", "Every quote, newest first: number, client, title, stage and total.", readOnly: true) { [self] _ in
                library.quotes.sorted { ($0.issued, $0.number) > ($1.issued, $1.number) }.map { quote -> [String: Any] in
                    ["number": quote.number, "client": clientName(quote.clientID), "title": quote.title,
                     "stage": quote.stage.rawValue, "issued": quote.issued.iso, "total": Self.dollars(quote.totals.total)]
                }
            },
            tool("list_clients", "Every client's name.", readOnly: true) { [self] _ in library.clients.map { ["name": $0.name] } },
            tool("open_quote", "Opens a quote in Quote Pilot so the user sees it.",
                 ["quote": Self.text("A quote number, like Q-0012.")], required: ["quote"]) { [self] arguments in
                guard arguments.values["quote"] is String else { throw MCPError("Pass quote: a quote number like Q-0012.") }
                let quote = try claudeTarget(arguments)
                openQuote(quote.id)
                return claudeJSON(quote)
            },
            tool("new_quote", "Starts a draft quote and opens it.",
                 ["client": Self.text("The client's name, as list_clients gives it. Optional."),
                  "title": Self.text("What the quote is for. Optional.")]) { [self] arguments in
                if let lockedError { throw lockedError }
                var clientID: UUID?
                if let name = arguments.string("client"), !name.isEmpty {
                    let partial = library.clients.filter { $0.name.localizedCaseInsensitiveContains(name) }
                    guard let client = library.clients.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame })
                            ?? (partial.count == 1 ? partial.first : nil) else {
                        throw MCPError("No single client matches \"\(name)\". The clients are: \(library.clients.map(\.name).joined(separator: ", ")). Leave client out to start the quote without one.")
                    }
                    clientID = client.id
                }
                var created: UUID?
                if let error = tryChange({ library in
                    var quote = library.newQuote(on: today, clientID: clientID)
                    quote.title = arguments.string("title") ?? ""
                    try library.update(quote)
                    created = quote.id
                }) { throw error }
                guard let quote = created.flatMap({ library.quote($0) }) else { throw MCPError("The quote wasn't saved.") }
                note("Claude started \(quote.number)")
                openQuote(quote.id)
                return claudeJSON(quote)
            },
            tool("add_quote_lines", "Adds lines to the end of a draft quote.",
                 ["quote": quote, "lines": ["type": "array", "items": ["type": "object", "properties": lineFields, "required": ["title"]]]],
                 required: ["lines"]) { [self] arguments in
                let quote = try claudeTarget(arguments)
                guard let items = arguments.list("lines"), !items.isEmpty else {
                    throw MCPError("Pass lines: a list of {title, detail, quantity, unit, rate}.")
                }
                guard items.count <= 200 else { throw MCPError("Add at most 200 lines at a time.") }
                let hourly = library.brand.hourlyRate
                let lines = try items.map { item in
                    // With neither unit nor rate, a line starts as Add Line's does: hours at the hourly rate.
                    let start = item.values["unit"] == nil && item.values["rate"] == nil
                        ? LineItem.blank(hourlyRate: hourly) : LineItem(title: "", rate: .zero)
                    let line = try claudeLine(item, to: start).withHourlyRate(hourly, after: nil)
                    guard !line.title.isEmpty else { throw MCPError("Every line needs a title.") }
                    return line
                }
                return claudeJSON(try claudeEdit(quote, "added \(lines.count) line\(lines.count == 1 ? "" : "s")") { quote in
                    lines.forEach { quote.addLine($0) }
                })
            },
            tool("update_quote_line", "Changes one line of a draft quote; only the fields given change.",
                 lineFields.merging(["quote": quote, "line": Self.text("The line's ID, like 03.")]) { $1 },
                 required: ["line"]) { [self] arguments in
                let quote = try claudeTarget(arguments)
                guard let code = arguments.lineCode("line"), let index = quote.lines.firstIndex(where: { $0.code == code }) else {
                    throw Self.noLine(quote, "\(arguments.values["line"] ?? "")")
                }
                let previous = quote.lines[index]
                let line = try claudeLine(arguments, to: previous).withHourlyRate(library.brand.hourlyRate, after: previous)
                return claudeJSON(try claudeEdit(quote, "changed line \(code)") { $0.lines[index] = line })
            },
            tool("remove_quote_lines", "Removes lines from a draft quote. The lines after them renumber.",
                 ["quote": quote, "lines": ["type": "array", "items": ["type": "string"], "description": "Line IDs, like [\"03\", \"04\"]."]],
                 required: ["lines"]) { [self] arguments in
                let quote = try claudeTarget(arguments)
                let codes = arguments.lineCodes("lines")
                guard !codes.isEmpty else { throw MCPError("Pass lines: the IDs to remove, like [\"03\"].") }
                let missing = codes.filter { code in !quote.lines.contains { $0.code == code } }
                guard missing.isEmpty else { throw Self.noLine(quote, missing.joined(separator: ", ")) }
                return claudeJSON(try claudeEdit(quote, "removed \(codes.count) line\(codes.count == 1 ? "" : "s")") { quote in
                    quote.lines.removeAll { codes.contains($0.code) }
                })
            },
            tool("set_quote_details", "Sets a draft quote's title, Work summary, Included / Not included lists, terms or payment plan. Only the fields given change.",
                 ["quote": quote, "title": ["type": "string"],
                  "summary": Self.text("The Work summary. Lines starting with \"-\" print as dot points."),
                  "included": items, "not_included": items, "terms": Self.text("The quote's Terms, printed at the end of the quote."),
                  "plan": ["type": "string", "enum": Self.plans.keys.sorted(),
                           "description": "fifty_fifty: a 50% deposit invoice, then the rest when the job is complete. full_amount: one invoice for the whole amount."]]) { [self] arguments in
                let quote = try claudeTarget(arguments)
                let title = arguments.string("title"), summary = arguments.string("summary"), terms = arguments.string("terms")
                let included = arguments.strings("included"), notIncluded = arguments.strings("not_included")
                let plan = try arguments.value("plan", { Self.plans[$0.lowercased()] }, else: "plan must be fifty_fifty or full_amount.")
                let names = [(title != nil, "title"), (summary != nil, "Work summary"), (included != nil, "Included list"),
                             (notIncluded != nil, "Not included list"), (terms != nil, "terms"), (plan != nil, "payment plan")].filter(\.0).map(\.1)
                guard !names.isEmpty else { throw MCPError("Pass at least one of title, summary, included, not_included, terms or plan.") }
                return claudeJSON(try claudeEdit(quote, "set the \(names.joined(separator: ", "))") { quote in
                    quote.title = title ?? quote.title
                    quote.summary = summary ?? quote.summary
                    quote.included = included ?? quote.included
                    quote.notIncluded = notIncluded ?? quote.notIncluded
                    quote.terms = terms ?? quote.terms
                    quote.plan = plan ?? quote.plan
                })
            },
        ])
    }

    /// One of Claude's tools. Each call that works is counted (`claude_tool`).
    private func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = [],
                      readOnly: Bool = false, run: @escaping (ClaudeArguments) throws -> Any) -> MCPTool {
        MCPTool(name: name, description: description, properties: properties, required: required, readOnly: readOnly) { [self] arguments in
            let result = try run(ClaudeArguments(values: arguments))
            track(.claudeTool, ["tool": name])
            return result
        }
    }

    /// The payment plans, as Claude names them.
    private static let plans: [String: PaymentPlan] = ["fifty_fifty": .fiftyFifty, "full_amount": .fullAmount]

    private static func text(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

    private static func noLine(_ quote: Quote, _ codes: String) -> MCPError {
        MCPError("\(quote.number) has no line \(codes). Its lines are \(quote.lines.map(\.code).joined(separator: ", ")).")
    }

    private var claudeView: [String: Any] {
        let rate = library.brand.hourlyRate.flatMap { $0 > .zero ? Self.dollars($0) : nil }
        var view: [String: Any] = ["section": "\(section)", "locked": isLocked, "hourly_rate": rate.map { $0 as Any } ?? NSNull(),
                                   "gst_registered": library.brand.gstRegistered]
        if let id = openQuoteID, let quote = library.quote(id) {
            view["open_quote"] = claudeJSON(quote)
        } else if section == .quotes, let id = selectedQuoteID, let quote = library.quote(id) {
            view["selected_quote"] = claudeJSON(quote)
        }
        if let id = openInvoiceID, let invoice = library.invoice(id) {
            view["open_invoice"] = ["number": invoice.number, "client": clientName(invoice.clientID), "stage": "\(invoice.stage)"]
        }
        if section == .clients, let id = selectedClientID, let client = library.client(id) {
            view["selected_client"] = client.name
        }
        return view
    }

    private func claudeJSON(_ quote: Quote) -> [String: Any] {
        ["number": quote.number, "client": clientName(quote.clientID), "title": quote.title, "stage": quote.stage.rawValue,
         "editable": claudeEditProblem(quote) == nil,
         "plan": Self.plans.first { $0.value == quote.plan }?.key ?? "",
         "summary": quote.summary, "included": quote.included, "not_included": quote.notIncluded, "terms": quote.terms,
         "lines": quote.lines.map { line -> [String: Any] in
             ["line": line.code, "title": line.title, "detail": line.detail,
              "quantity": NSDecimalNumber(decimal: line.quantity).doubleValue, "unit": line.unit.rawValue,
              "rate": Self.dollars(line.rate), "amount": Self.dollars(line.amount)]
         },
         "subtotal": Self.dollars(quote.totals.subtotal), "gst": Self.dollars(quote.totals.gst), "total": Self.dollars(quote.totals.total)]
    }

    private func clientName(_ id: UUID?) -> String { id.flatMap { library.client($0)?.name } ?? "" }

    private static func dollars(_ amount: Money) -> Double { Double(amount.cents) / 100 }

    /// The quote named by `quote`, or else the one open (or selected in the Quotes list).
    private func claudeTarget(_ arguments: ClaudeArguments) throws -> Quote {
        if let number = arguments.string("quote"), !number.isEmpty {
            guard let quote = library.quote(number: number) else { throw MCPError("There's no quote \(number). list_quotes shows them all.") }
            return quote
        }
        guard let id = openQuoteID ?? (section == .quotes ? selectedQuoteID : nil), let quote = library.quote(id) else {
            throw MCPError("No quote is open in Quote Pilot. Pass a quote number, or start one with new_quote.")
        }
        return quote
    }

    /// `line` with the fields Claude gave: title, detail, quantity, unit and rate.
    private func claudeLine(_ fields: ClaudeArguments, to line: LineItem) throws -> LineItem {
        var line = line
        line.title = fields.string("title") ?? line.title
        line.detail = fields.string("detail") ?? line.detail
        line.unit = try fields.value("unit", { Unit(rawValue: $0.lowercased()) }, else: "unit must be hours, days or units.") ?? line.unit
        line.quantity = try fields.value("quantity", FieldParser.quantity,
                                         else: "quantity must be a number from 0, with at most two decimal places.") ?? line.quantity
        line.rate = try fields.value("rate", FieldParser.money, else: "rate must be a dollar amount, like 450 or 89.50.") ?? line.rate
        return line
    }
}

/// Claude's arguments to one tool, read by type. A value of the wrong type reads as left out.
struct ClaudeArguments {
    let values: [String: Any]

    /// Text, trimmed.
    func string(_ key: String) -> String? {
        (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A list of text, each item trimmed and blank ones dropped.
    func strings(_ key: String) -> [String]? {
        (values[key] as? [String])?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// A value given as text or a number, read by `parse`; refused with `problem` when it can't be.
    func value<T>(_ key: String, _ parse: (String) -> T?, else problem: String) throws -> T? {
        guard let value = values[key] else { return nil }
        guard let parsed = ((value as? NSNumber)?.stringValue ?? value as? String).flatMap(parse) else { throw MCPError(problem) }
        return parsed
    }

    /// A list of objects, such as the lines to add.
    func list(_ key: String) -> [ClaudeArguments]? { (values[key] as? [[String: Any]])?.map(ClaudeArguments.init) }

    func lineCode(_ key: String) -> String? { Self.lineCode(values[key]) }
    func lineCodes(_ key: String) -> [String] { (values[key] as? [Any] ?? []).compactMap(Self.lineCode) }

    /// A line ID: "3", 3 or "03" → "03".
    private static func lineCode(_ value: Any?) -> String? {
        if let number = value as? NSNumber { return String(format: "%02d", number.intValue) }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return Int(text).map { String(format: "%02d", $0) } ?? text
    }
}
