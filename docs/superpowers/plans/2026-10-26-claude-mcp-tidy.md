# Claude MCP Tidy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Quote Pilot's Claude link (released in 1.3.0) clean, production-grade code: shorter, one place per concern, the same behaviour.

**Architecture:** Three layers, one file each:
- `ClaudeServer.swift`: HTTP on 127.0.0.1.
- `MCP.swift`: JSON-RPC and MCP, knowing nothing about quotes.
- `ClaudeTools.swift`: Quote Pilot's tools as one table of `MCPTool` values.

`ClaudeLink.swift` keeps the Settings switch, the key and the port.

**Tech Stack:** Swift 6.4 toolchain in Swift 5 language mode, SwiftUI, Network.framework, Swift Testing. Build and test with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.

**Spec:** the user's requests on 26 Oct 2026:
- "Quote Pilot … can start its own MCP server … based on what the user is looking at … fill in the lines and add lines";
- "write clean, good code. If something can be written in ten lines as opposed to one hundred, do it. Clean production grade code".

The behaviour to keep is what 1.3.0 does: `README.md` → "Claude", and the tests in `Tests/QuotePilotUITests/ClaudeLinkTests.swift`.

## Global Constraints

- Keep the behaviour exactly as it is:
  - the same nine tool names, arguments and refusals;
  - drafts only; refused while the fee lock is on;
  - the Activity text "Claude added 3 lines on Q-0005";
  - 127.0.0.1:47210, Bearer key, 401/403/405/202 as now, off by default.
- Every existing test in `ClaudeLinkTests.swift` keeps passing. Tests may be renamed or moved to follow the new names, but no assertion is weakened.
- Fewer lines in total than now (the four files are 783 lines). Prefer standard library and Foundation over hand-rolled code. Don't add dependencies.
- Match the codebase's style: doc comments in plain English with "the user" wording, and no `// MARK` noise beyond what is there.
- One commit per distinct change, each ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Edit files only with the Edit/Write tools, never with shell redirects or `sed -i`.
- Never touch `~/Library/Application Support/Quote Pilot`, `~/.claude.json`, or the installed app.

## Review Focus

- **A request that never finishes** (a client opens a connection and sends nothing): the server must close it after about 10 seconds rather than hold it forever.
- **An unknown tool name in tools/call:** a JSON-RPC error -32602 ("Invalid params", as the MCP spec says), not an isError result.
- **A malformed or empty JSON body:** -32700 with id null, and the server keeps running.
- **Wrong key, or a request with a browser Origin:** 401 / 403, with nothing run.
- **Read-only tools carry MCP annotations** (`readOnlyHint: true`), so Claude Code can treat them as safe.

---

### Task 1: Split the Claude link into protocol, tools and server, shorter

**Files:**
- Create: `Sources/QuotePilotUI/App/MCP.swift`. It holds JSON-RPC dispatch (`initialize`, `ping`, `tools/list`, `tools/call`; notifications get no reply) and a small `MCPTool` type: name, description, input schema, read-only flag, and `run(arguments) throws -> Any`. It has no Quote Pilot types in it.
- Create: `Sources/QuotePilotUI/App/ClaudeTools.swift`. It holds Quote Pilot's nine tools as one array of `MCPTool`. Each tool's schema sits next to its handler, so there's no second list of names and no `switch`. It includes a small typed reader for arguments (string, strings, number, line code) so the handlers stay short. The server instructions text moves here too.
- Modify or delete: `Sources/QuotePilotUI/App/AppModel+Claude.swift`. Keep only what has to be on `AppModel`:
  - the HTTP answer: path, Origin, key, method;
  - `claudeLine` and `copyClaudeSetupCommand`;
  - the draft-quote edit helper.
- Modify: `Sources/QuotePilotUI/App/ClaudeServer.swift`. Close idle or unfinished connections after 10 seconds. Keep the parser small.
- Modify: `Sources/QuotePilotUI/App/ClaudeLink.swift`. Check the key in constant time. Simplify how `AppModel` hands it the answer closure if a simpler way exists: today it is wired in `AppModel.init` and again in `claude`'s didSet.
- Test: `Tests/QuotePilotUITests/ClaudeLinkTests.swift`. Adjust it to the new names. Add tests for:
  - unknown tool → -32602;
  - a malformed body → -32700;
  - read-only annotations on `get_current_view`, `list_quotes` and `list_clients`;
  - the server closing a silent connection. Use a short timeout injected for the test, not a 10 s wait.

**Interfaces:**
- Consumes the existing `AppModel` API: `library`, `openQuote(_:)`, `tryChange`, `note`, `track(.claudeTool, …)`, `isLocked`, `lockedError`, `openQuoteID`, `selectedQuoteID`, `section`, `today`, `now()`, `FieldParser.money/quantity`, `LineItem.startingUnit/withHourlyRate`, `Quote.addLine`.
- Produces the same Settings-facing API `BrandView.swift` uses: `model.claude.isOn`, `model.claudeLine`, `model.copyClaudeSetupCommand()`. Leave `BrandView.swift` unchanged.

- [ ] **Step 1:** Read the four files and the README "Claude" section. Write the new layout.
- [ ] **Step 2:** Add the new tests (the -32602, -32700, annotation and idle-timeout cases). Run them and see them fail.
- [ ] **Step 3:** Implement. Run `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test --filter "ClaudeLinkTests|UsageTests|Brand"` until everything passes.
- [ ] **Step 4:** Run `wc -l` on the files, which must total under 783. Commit one change at a time.
