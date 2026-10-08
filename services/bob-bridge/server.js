/**
 * bob-bridge/server.js
 *
 * Lightweight relay. Accepts a plain-English trick description from the
 * browser, forwards it to bob-host-agent.sh on the Ubuntu host via a Unix
 * socket, and returns the generated CommandScript JSON.
 *
 * The host agent handles Bob Shell and docker-compose — this container
 * just does the HTTP ↔ socket translation.
 *
 * POST /generate
 *   Body:    { "prompt": "do a figure 8" }
 *   Returns: CommandScript JSON  { name, description, steps: [...] }
 *            or  { error: "..." }  with HTTP 4xx/5xx
 *
 * Socket path is bind-mounted from the host at /tmp/bob-host-agent.sock
 * (see docker-compose.yml). Start bob-host-agent.sh before using Generate.
 */

"use strict";

const express = require("express");
const cors = require("cors");
const net = require("net");

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.BOB_BRIDGE_PORT || 4000;
const SOCKET_PATH = process.env.HOST_AGENT_SOCKET || "/tmp/bob-host-agent.sock";

// ─── Health check ─────────────────────────────────────────────────────────────
app.get("/health", (_req, res) => res.json({ status: "ok" }));

// ─── Generate endpoint ────────────────────────────────────────────────────────
app.post("/generate", (req, res) => {
  const prompt = (req.body && req.body.prompt || "").trim();
  if (!prompt) {
    return res.status(400).json({ error: "prompt is required" });
  }

  console.log(`[bob-bridge] Forwarding to host agent: "${prompt}"`);

  const safePrompt = prompt.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const request = JSON.stringify({ prompt: safePrompt }) + "\n";

  let responseData = "";
  let responded = false;

  const socket = net.createConnection(SOCKET_PATH, () => {
    socket.write(request);
  });

  // Host agent may take up to 5 min (Bob Shell + docker build)
  socket.setTimeout(300_000);

  socket.on("data", (chunk) => {
    responseData += chunk.toString();
  });

  socket.on("end", () => {
    if (responded) return;
    responded = true;

    let parsed;
    try {
      const firstLine = responseData.split("\n").find(l => l.trim().startsWith("{"));
      parsed = JSON.parse(firstLine || responseData);
    } catch {
      console.error("[bob-bridge] Invalid JSON from host agent:", responseData);
      return res.status(500).json({ error: "Host agent returned invalid JSON" });
    }

    if (!parsed.ok) {
      console.error("[bob-bridge] Host agent error:", parsed.error);
      return res.status(500).json({ error: parsed.error || "Host agent failed" });
    }

    const script = parsed.script;
    if (!script || !script.name || !Array.isArray(script.steps)) {
      return res.status(500).json({
        error: "Generated script is missing required fields (name, steps)",
        script,
      });
    }

    console.log(`[bob-bridge] Generated "${script.name}" (${script.steps.length} steps)`);
    return res.json(script);
  });

  socket.on("timeout", () => {
    if (responded) return;
    responded = true;
    socket.destroy();
    console.error("[bob-bridge] Host agent timed out");
    res.status(504).json({ error: "Host agent timed out — Bob or docker build took too long" });
  });

  socket.on("error", (err) => {
    if (responded) return;
    responded = true;
    console.error("[bob-bridge] Socket error:", err.message);
    if (err.code === "ENOENT") {
      res.status(503).json({
        error: "Host agent is not running. Start it with: ./bob-host-agent.sh",
      });
    } else {
      res.status(500).json({ error: `Socket error: ${err.message}` });
    }
  });
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`[bob-bridge] Listening on http://127.0.0.1:${PORT}`);
  console.log(`[bob-bridge] Host agent socket: ${SOCKET_PATH}`);
});
