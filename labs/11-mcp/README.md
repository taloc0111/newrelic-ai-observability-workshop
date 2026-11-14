# Lab 8 (optional) - New Relic Ground Truth (MCP server) from your IDE agent

Ground Truth is the GA name (Sep 2026) of the New Relic AI MCP Server. An MCP-capable client (GitHub Copilot, Claude Code, Claude Desktop, Cursor, ChatGPT, Azure SRE Agent) calls New Relic tools: run NRQL, list entities, read issues, read AI monitoring data. It is the "agentic" pillar you can touch without buying Autopilot.

Endpoint: `https://mcp.newrelic.com/mcp/` (EU: `https://mcp.eu.newrelic.com/mcp/`). Auth is **OAuth**: the client opens a browser, you log in to New Relic, no key in any file.

1. Connect the client:
   - **VS Code / Copilot**: copy `mcp.json` to `.vscode/mcp.json`, reload, accept the OAuth prompt.
   - **Claude Code**: `claude mcp add --transport http --scope user newrelic https://mcp.newrelic.com/mcp/`, then either `claude mcp login newrelic` (2.1.186 or later) or, on older builds, start a new session and run `/mcp` -> newrelic -> **Authenticate** (verified on 2.1.177: `claude mcp login` does not exist there). A session only connects servers at start-up, so open a new one after adding.
   - An `api-key: NRAK-...` header still works for clients without OAuth, but only after an admin enables **API Keys** for Ground Truth (off by default), and some tools are OAuth-only.
   - If the browser ends on **"access_denied: Your administrator has disabled access to this application ... can be enabled through New Relic Feature Control Manager"**, Ground Truth is switched off for the account (the default on a fresh account in the rehearsal). An admin enables it under **Administration -> Feature Control** (New Relic MCP Server / Ground Truth), then run the login again. The login must run in a real terminal; it cannot be scripted.
2. Confirm the server lists tools (`/mcp` in Claude Code).
3. Ask, in order, and compare with the Lab 4 answers:
   - `Which New Relic account can you see, and which APM applications report in the last hour?`
   - `Run NRQL: error rate of SimplCommerce per minute for the last 30 minutes.`
   - `List open issues and the condition that opened each.`
   - `Why did SimplCommerce fail in the last hour? Use issues, Kubernetes events and logs from namespace simplcommerce.`
4. Notice: the agent chooses the tool calls; read the NRQL it ran before trusting the number (same rule as Lab 4). Tool calls run with your user's permissions. Billing: Ground Truth is available on every pricing model, most tools are metered as **Core CCUs**, and four tools (the ones that call New Relic AI) are metered as Advanced CCUs and need the Advanced Compute add-on.

Status: config rewritten for OAuth on 2026-11-07 from the docs. **Not runnable on the course account:** Feature Control lists only "New Relic AI", there is no MCP Server row to activate, and the OAuth login is refused with access_denied. The lab is a talk track until an account with that switch is available.
