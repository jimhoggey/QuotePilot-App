import Foundation
import Network
import QuotePilotCore
import Testing
@testable import QuotePilotUI

/// Let Claude use Quote Pilot: the server on this Mac with its key, the MCP messages, and what the
/// tools may and may not change. Made-up data; the one server here is on a free loopback port.
@MainActor
@Suite struct ClaudeLinkTests {
    /// One JSON-RPC message to the model's MCP server, and its reply.
    func rpc(_ model: AppModel, _ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        let body = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        return model.claudeMCP.reply(to: body).map { json(String(decoding: $0, as: UTF8.self)) } ?? [:]
    }

    func call(_ model: AppModel, _ tool: String, _ arguments: [String: Any] = [:]) -> (text: String, isError: Bool) {
        let result = rpc(model, "tools/call", ["name": tool, "arguments": arguments])["result"] as? [String: Any] ?? [:]
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return (text, result["isError"] as? Bool ?? true)
    }

    func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    /// The sample business with a $120 hourly rate and a new draft quote open.
    func modelWithDraft() throws -> AppModel {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.hourlyRate = Money(dollars: 120)
        model.updateBrand(brand)
        model.newQuote()
        return model
    }

    @Test func theServerAnswersOnlyWithTheKey() async throws {
        let model = try UIFixture.sampleModel()
        model.claude = ClaudeLink(settings: nil, port: 0)
        model.claude.isOn = true
        defer { model.claude.isOn = false }
        for _ in 0..<200 where model.claude.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let port = try #require(model.claude.port)
        #expect(model.claudeLine == "On, at http://127.0.0.1:\(port)/mcp")
        #expect(model.claude.setupCommand.contains("--header \"Authorization: Bearer \(model.claude.key)\""))

        func post(_ body: String, key: String?, method: String = "POST", origin: String? = nil) async throws -> (Int, [String: Any]) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
            request.httpMethod = method
            if method == "POST" { request.httpBody = Data(body.utf8) }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
        #expect(try await post(initialize, key: nil).0 == 401)
        #expect(try await post(initialize, key: "wrong").0 == 401)
        #expect(try await post(initialize, key: model.claude.key, origin: "https://example.com").0 == 403)
        #expect(try await post("", key: model.claude.key, method: "GET").0 == 405)
        let (badStatus, bad) = try await post("{", key: model.claude.key)
        #expect(badStatus == 200 && (bad["error"] as? [String: Any])?["code"] as? Int == -32700)
        let (status, reply) = try await post(initialize, key: model.claude.key)
        #expect(status == 200)
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "quote-pilot")
        #expect(try await post(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, key: model.claude.key).0 == 202)
    }

    @Test func theServerHangsUpOnASilentConnection() async throws {
        let server = try ClaudeServer(port: 0, timeout: 0.1) { _ in .init(status: 200) }
        defer { server.stop() }
        let port = await withCheckedContinuation { done in server.start { done.resume(returning: (try? $0.get()) ?? 0) } }
        let connection = NWConnection(host: "127.0.0.1", port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
        connection.start(queue: .global())
        // It sends nothing. The server should hang up long before this side gives up, 5 seconds on.
        // Timed in the callback, off the main actor, so other tests can't slow the clock.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { connection.cancel() }
        let started = ContinuousClock.now
        let hungUpAfter = await withCheckedContinuation { done in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                done.resume(returning: ContinuousClock.now - started)
            }
        }
        #expect(hungUpAfter < .seconds(2))
    }

    @Test func offByDefaultAndTheKeyIsKept() {
        let settings = UserDefaults(suiteName: "ClaudeLinkTests-\(UUID().uuidString)")!
        let first = ClaudeLink(settings: settings)
        #expect(!first.isOn)
        #expect(first.key.count == 64)
        #expect(ClaudeLink(settings: settings).key == first.key)
    }

    @Test func theToolsAreListed() throws {
        let model = try UIFixture.sampleModel()
        let tools = try #require((rpc(model, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            "get_current_view", "list_quotes", "list_clients", "open_quote", "new_quote",
            "add_quote_lines", "update_quote_line", "remove_quote_lines", "set_quote_text",
        ])
        let readOnly = tools.filter { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true }
        #expect(readOnly.compactMap { $0["name"] as? String } == ["get_current_view", "list_quotes", "list_clients"])
        #expect(tools.allSatisfy { ($0["annotations"] as? [String: Any])?["readOnlyHint"] is Bool }, "every tool says")
    }

    @Test func aMalformedOrEmptyBodyIsAParseError() throws {
        let model = try UIFixture.sampleModel()
        for body in ["", "{not json", #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#] {
            let reply = json(String(decoding: try #require(model.claudeMCP.reply(to: Data(body.utf8))), as: UTF8.self))
            #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32700, "\(body)")
            #expect(reply["id"] is NSNull, "\(body)")
        }
        #expect(rpc(model, "ping")["result"] != nil, "it keeps answering")
    }

    @Test func claudeFillsTheOpenDraft() throws {
        let model = try modelWithDraft()
        let quote = try #require(model.openQuoteID.flatMap { model.library.quote($0) })
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
        let text = call(model, "set_quote_text", ["title": "Website improvements", "included": ["Testing", " "], "not_included": ["Copywriting"]])
        #expect(!text.isError)
        let changed = try #require(model.library.quote(quote.id))
        #expect(changed.lines.map(\.title) == ["Hosting and domain", "Speed tune-up"])
        #expect(changed.lines.map(\.code) == ["01", "02"], "drafts renumber")
        #expect(changed.title == "Website improvements")
        #expect(changed.included == ["Testing"] && changed.notIncluded == ["Copywriting"])
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
        #expect(call(locked, "new_quote").isError)
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
