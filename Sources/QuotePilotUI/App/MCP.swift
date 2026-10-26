import Foundation

/// One tool Claude can call over MCP: what it's for, the arguments it takes and what it does.
struct MCPTool {
    let name: String
    let description: String
    /// Its arguments' JSON Schema properties, and the ones it can't do without.
    var properties: [String: Any] = [:]
    var required: [String] = []
    /// A tool that only reads, so Claude Code can treat it as safe (`readOnlyHint`).
    var readOnly = false
    /// What it does with Claude's arguments. What it returns goes back as JSON; what it throws goes
    /// back as text with isError, so Claude can read why.
    let run: ([String: Any]) throws -> Any

    /// How `tools/list` describes it.
    var listing: [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema, "annotations": ["readOnlyHint": readOnly]]
    }
}

/// What a tool refuses with: the words Claude reads back.
struct MCPError: LocalizedError {
    let errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

/// The MCP side of a JSON-RPC 2.0 conversation: `initialize`, `ping`, `tools/list` and `tools/call`.
/// It knows nothing about quotes; the tools do the work, and `ClaudeServer` carries the messages.
struct MCPServer {
    /// The protocol versions it speaks, newest first.
    static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let name: String
    let version: String
    let instructions: String
    let tools: [MCPTool]

    /// The reply to one JSON-RPC message; nil for a notification, which gets none.
    func reply(to body: Data) -> Data? {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = message["method"] as? String
        else { return Self.error(NSNull(), -32700, "Parse error: send one JSON-RPC request") }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        let result: Any
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            result = ["protocolVersion": Self.versions.contains(asked) ? asked : Self.versions[0],
                      "capabilities": ["tools": ["listChanged": false]],
                      "serverInfo": ["name": name, "version": version], "instructions": instructions]
        case "ping":
            result = [String: Any]()
        case "tools/list":
            result = ["tools": tools.map(\.listing)]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard let tool = tools.first(where: { $0.name == name }) else {
                return Self.error(id, -32602, "Unknown tool: \(name). tools/list shows them all.")
            }
            result = Self.call(tool, params["arguments"] as? [String: Any] ?? [:])
        default:
            return Self.error(id, -32601, "Method not found: \(method)")
        }
        // nil means "no reply" (a notification), so a reply that can't be written is an error instead.
        return Self.json(["jsonrpc": "2.0", "id": id, "result": result]) ?? Self.error(id, -32603, "Internal error: the reply couldn't be written.")
    }

    /// What a tool gives back: its result as JSON text, or why it refused, marked isError.
    private static func call(_ tool: MCPTool, _ arguments: [String: Any]) -> [String: Any] {
        do {
            guard let result = json(try tool.run(arguments)) else { throw MCPError("The result couldn't be read.") }
            return ["content": [["type": "text", "text": String(decoding: result, as: UTF8.self)]], "isError": false]
        } catch {
            return ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
        }
    }

    private static func error(_ id: Any, _ code: Int, _ message: String) -> Data? {
        json(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    /// `object` as JSON; nil for something JSON can't hold, which JSONSerialization would crash on.
    private static func json(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
