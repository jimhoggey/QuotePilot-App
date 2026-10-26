import Foundation
import Network
import QuotePilotCore
import Testing
@testable import QuotePilotUI

/// Let Claude use Quote Pilot: the server on this Mac with its key, the MCP messages, and what the
/// tools may and may not change. Made-up data; the servers here are on free loopback ports.
@MainActor
@Suite struct ClaudeLinkTests {
    /// One JSON-RPC message to the model's MCP server, and its reply.
    func rpc(_ model: AppModel, _ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        let body = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        return model.claudeMCP.reply(to: body).map(json) ?? [:]
    }

    func call(_ model: AppModel, _ tool: String, _ arguments: [String: Any] = [:]) -> (text: String, isError: Bool) {
        let result = rpc(model, "tools/call", ["name": tool, "arguments": arguments])["result"] as? [String: Any] ?? [:]
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return (text, result["isError"] as? Bool ?? true)
    }

    func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
    func json(_ text: String) -> [String: Any] { json(Data(text.utf8)) }

    /// The sample business with a $120 hourly rate and a new draft quote open.
    func modelWithDraft() throws -> (AppModel, Quote) {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.hourlyRate = Money(dollars: 120)
        model.updateBrand(brand)
        model.newQuote()
        return (model, try #require(model.openQuoteID.flatMap { model.library.quote($0) }))
    }

    @Test func theServerAnswersOnlyWithTheKey() async throws {
        let model = try UIFixture.sampleModel()
        model.claude = model.makeClaudeLink(settings: nil, port: 0)
        model.claude.isOn = true
        defer { model.claude.isOn = false }
        for _ in 0..<200 where model.claude.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let port = try #require(model.claude.port)
        #expect(model.claudeLine == "On, at http://127.0.0.1:\(port)/mcp")
        #expect(model.claude.setupCommand.contains("--header \"Authorization: Bearer \(model.claude.key)\""))

        func post(_ body: String, key: String?, method: String = "POST", origin: String? = nil) async throws -> (Int, [String: Any]) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
            request.httpMethod = method
            request.httpBody = method == "POST" ? Data(body.utf8) : nil
            request.allHTTPHeaderFields = ["Content-Type": "application/json", "Authorization": key.map { "Bearer \($0)" }, "Origin": origin]
                .compactMapValues { $0 }
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, json(data))
        }
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
        #expect(try await post(initialize, key: nil).0 == 401)
        #expect(try await post(initialize, key: "wrong").0 == 401)
        #expect(try await post(initialize, key: model.claude.key, origin: "https://example.com").0 == 403)
        #expect(try await post("", key: model.claude.key, method: "GET").0 == 405)
        for body in ["", "{not json", #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#] {
            let (status, reply) = try await post(body, key: model.claude.key)
            #expect(status == 200 && (reply["error"] as? [String: Any])?["code"] as? Int == -32700 && reply["id"] is NSNull, "\(body)")
        }
        let (status, reply) = try await post(initialize, key: model.claude.key)
        #expect(status == 200, "it keeps answering after a bad body")
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "quote-pilot")
        #expect((result["instructions"] as? String)?.contains("terms and the payment plan") == true)
        #expect(try await post(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, key: model.claude.key).0 == 202)
    }

    @Test func theServerHangsUpOnASilentConnection() async throws {
        let server = try ClaudeServer(port: 0, timeout: 0.1) { _ in .init(status: 200) }
        defer { server.stop() }
        let port = await withCheckedContinuation { done in server.start { done.resume(returning: (try? $0.get()) ?? 0) } }
        let connection = NWConnection(host: "127.0.0.1", port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
        connection.start(queue: .global())
        // It sends nothing. The server should hang up long before this side gives up, 5 seconds on;
        // timed in the callback, off the main actor, so other tests can't slow the clock.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { connection.cancel() }
        let started = ContinuousClock.now
        let hungUpAfter = await withCheckedContinuation { done in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in done.resume(returning: ContinuousClock.now - started) }
        }
        #expect(hungUpAfter < .seconds(2))
    }

    @Test func offByDefaultAndTheKeyIsKept() throws {
        let settings = UserDefaults(suiteName: "ClaudeLinkTests-\(UUID().uuidString)")!
        let model = try UIFixture.sampleModel()
        let first = model.makeClaudeLink(settings: settings)
        #expect(!first.isOn)
        #expect(first.key.count == 64)
        #expect(model.makeClaudeLink(settings: settings).key == first.key)
        let wrong = String(first.key.dropLast()) + (first.key.hasSuffix("0") ? "1" : "0")
        #expect(first.accepts("Bearer \(first.key)") && !first.accepts("Bearer \(wrong)") && !first.accepts(nil))
    }

    @Test func theToolsAreListed() throws {
        let model = try UIFixture.sampleModel()
        let tools = try #require((rpc(model, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            "get_current_view", "list_quotes", "list_clients", "open_quote", "new_quote",
            "add_quote_lines", "update_quote_line", "remove_quote_lines", "set_quote_details",
        ])
        let readOnly = tools.filter { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true }
        #expect(readOnly.compactMap { $0["name"] as? String } == ["get_current_view", "list_quotes", "list_clients"])
    }

    @Test func claudeFillsTheOpenDraft() throws {
        let (model, quote) = try modelWithDraft()
        let added = call(model, "add_quote_lines", ["lines": [
            ["title": "Contact form", "detail": "Name, email and message, sent to your inbox.", "quantity": 3],
            ["title": "Hosting setup", "rate": 450],
            ["title": "Speed tune-up", "quantity": 1.5, "unit": "hours"],
        ]])
        #expect(!added.isError, "\(added.text)")
        let lines = try #require(model.library.quote(quote.id)?.lines)
        #expect(lines.map(\.title) == ["Contact form", "Hosting setup", "Speed tune-up"])
        #expect(lines[0].unit == .hours && lines[0].rate == Money(dollars: 120), "hours at the hourly rate")
        #expect(lines[1].unit == .units && lines[1].rate == Money(dollars: 450))
        #expect(lines[2].quantity == Decimal(string: "1.5"))
        #expect(model.library.activity.first?.message == "Claude added 3 lines on \(quote.number)")
        #expect((json(added.text)["subtotal"] as? NSNumber)?.doubleValue == 990)

        #expect(!call(model, "update_quote_line", ["line": 2, "title": "Hosting and domain"]).isError)
        #expect(!call(model, "remove_quote_lines", ["lines": ["01"]]).isError)
        let text = call(model, "set_quote_details", ["title": "Website improvements", "included": ["Testing", " "], "not_included": ["Copywriting"]])
        #expect(!text.isError)
        let changed = try #require(model.library.quote(quote.id))
        #expect(changed.lines.map(\.title) == ["Hosting and domain", "Speed tune-up"])
        #expect(changed.lines.map(\.code) == ["01", "02"], "drafts renumber")
        #expect(changed.title == "Website improvements")
        #expect(changed.included == ["Testing"] && changed.notIncluded == ["Copywriting"])
    }

    @Test func claudeSetsThePaymentPlan() throws {
        let (model, quote) = try modelWithDraft()
        #expect((json(call(model, "get_current_view").text)["open_quote"] as? [String: Any])?["plan"] as? String == "fifty_fifty")
        let set = call(model, "set_quote_details", ["plan": "full_amount"])
        #expect(!set.isError && json(set.text)["plan"] as? String == "full_amount", "\(set.text)")
        #expect(model.library.quote(quote.id)?.plan == .fullAmount)
        #expect(model.library.activity.first?.message == "Claude set the payment plan on \(quote.number)")
        let refused = call(model, "set_quote_details", ["plan": "weekly"])
        #expect(refused.isError && refused.text == "plan must be fifty_fifty or full_amount.")
        #expect(model.library.quote(quote.id)?.plan == .fullAmount)
    }

    @Test func claudeSetsTheTerms() throws {
        let (model, quote) = try modelWithDraft()
        let set = call(model, "set_quote_details", ["terms": " Payment within 14 days.\n"])
        #expect(!set.isError && json(set.text)["terms"] as? String == "Payment within 14 days.", "\(set.text)")
        #expect(model.library.quote(quote.id)?.terms == "Payment within 14 days.")
        #expect(model.library.activity.first?.message == "Claude set the terms on \(quote.number)")
    }

    @Test func onlyNewLinesNeedATitle() throws {
        let (model, quote) = try modelWithDraft()
        #expect(call(model, "add_quote_lines", ["lines": [["title": " "]]]).text == "Every line needs a title.")
        #expect(!call(model, "add_quote_lines", ["lines": [["title": "Setup"]]]).isError)
        let blanked = call(model, "update_quote_line", ["line": "01", "title": ""])
        #expect(!blanked.isError, "\(blanked.text)")
        #expect(!call(model, "update_quote_line", ["line": 1, "rate": 100]).isError, "a blank line can still change")
        let line = try #require(model.library.quote(quote.id)?.lines.first)
        #expect(line.title == "" && line.rate == Money(dollars: 100))
    }

    @Test func sentQuotesAndTheLockAreLeftAlone() throws {
        let model = try UIFixture.sampleModel()
        let sent = try #require(model.library.quotes.first { $0.stage != .draft })
        let refused = call(model, "add_quote_lines", ["quote": sent.number, "lines": [["title": "Extra"]]])
        #expect(refused.isError && refused.text.contains("has been sent"))
        #expect(model.library.quote(sent.id)?.lines == sent.lines)
        #expect(call(model, "add_quote_lines", ["quote": "Q-9999", "lines": [["title": "Extra"]]]).isError)
        let unknown = rpc(model, "tools/call", ["name": "send_quote"])["error"] as? [String: Any]
        #expect(unknown?["code"] as? Int == -32602, "there's no such tool: Invalid params")

        let locked = try FeeBarTests().lockedModel()
        let draft = try #require(locked.library.quotes.first { $0.stage == .draft })
        let lockedReply = call(locked, "add_quote_lines", ["quote": draft.number, "lines": [["title": "Extra"]]])
        #expect(lockedReply.isError && lockedReply.text.contains("locked"))
        let lockedNew = call(locked, "new_quote")
        #expect(lockedNew.isError && lockedNew.text == lockedReply.text, "one lock message")
    }

    @Test func newQuoteFindsTheClientAndOpensIt() throws {
        let model = try UIFixture.sampleModel()
        let client = try #require(model.library.clients.first)
        let made = call(model, "new_quote", ["client": client.name.uppercased(), "title": "Next improvements"])
        #expect(!made.isError, "\(made.text)")
        let quote = try #require(model.openQuoteID.flatMap { model.library.quote($0) })
        #expect(quote.clientID == client.id && quote.title == "Next improvements" && quote.stage == .draft)
        let view = json(call(model, "get_current_view").text)
        #expect((view["open_quote"] as? [String: Any])?["number"] as? String == quote.number)
        #expect(call(model, "new_quote", ["client": "Nobody At All"]).isError)
    }
}
