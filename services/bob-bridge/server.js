/**
 * bob-bridge/server.js
 *
 * Minimal Express sidecar that accepts a plain-English trick description,
 * shells out to the Bob CLI with the rover-spec rules loaded, and returns
 * the generated CommandScript JSON so the browser UI can execute it
 * immediately — no Docker rebuild required.
 *
 * POST /generate
 *   Body: { "prompt": "do a figure 8" }
 *   Returns: CommandScript JSON  { name, description, steps: [...] }
 *            or  { error: "..." }  with HTTP 4xx/5xx
 *
 * The Bob CLI must be installed inside the container (see Dockerfile).
 * The workspace is mounted at /workspace so Bob finds .bob/rules/ and
 * specs/free-roam-spec.md.
 */

"use strict";

const express = require("express");
const cors = require("cors");
const { execFile } = require("child_process");
const path = require("path");
const fs = require("fs");

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.BOB_BRIDGE_PORT || 4000;
const WORKSPACE = process.env.BOB_WORKSPACE || "/workspace";
const SCRIPTS_DIR = path.join(WORKSPACE, "specs", "scripts");

// ─── Health check ─────────────────────────────────────────────────────────────
app.get("/health", (_req, res) => res.json({ status: "ok" }));

// ─── Generate endpoint ────────────────────────────────────────────────────────
app.post("/generate", (req, res) => {
  const prompt = (req.body && req.body.prompt || "").trim();
  if (!prompt) {
    return res.status(400).json({ error: "prompt is required" });
  }

  // Snapshot the scripts directory before the Bob run so we can detect the
  // new file Bob writes.
  let beforeFiles;
  try {
    beforeFiles = new Set(fs.readdirSync(SCRIPTS_DIR));
  } catch {
    beforeFiles = new Set();
  }

  // Bob Shell non-interactive: bob -p "prompt"
  // cwd is set to WORKSPACE so Bob loads .bob/rules/ and the rover-spec skill.
  const bobPrompt = [
    "You are operating under the rover-spec skill.",
    "Follow the rover-spec skill instructions exactly.",
    "Generate a rover trick script for this description:",
    prompt,
  ].join(" ");

  const args = ["-p", bobPrompt];

  execFile("bob", args, { timeout: 120_000, cwd: WORKSPACE }, (err, stdout, stderr) => {
    if (err) {
      console.error("[bob-bridge] Bob CLI error:", stderr || err.message);
      return res.status(500).json({
        error: "Bob CLI failed",
        detail: stderr || err.message,
      });
    }

    // Find the new JSON file Bob wrote to specs/scripts/
    let afterFiles;
    try {
      afterFiles = new Set(fs.readdirSync(SCRIPTS_DIR));
    } catch {
      return res.status(500).json({ error: "Could not read scripts directory after generation" });
    }

    const newFiles = [...afterFiles].filter(
      (f) => !beforeFiles.has(f) && f.endsWith(".json")
    );

    if (newFiles.length === 0) {
      // Bob may have updated an existing script — try to parse the script name
      // from its stdout output (looks for "specs/scripts/<name>.json")
      const match = stdout.match(/specs\/scripts\/([\w-]+\.json)/);
      if (match) {
        newFiles.push(match[1]);
      }
    }

    if (newFiles.length === 0) {
      console.error("[bob-bridge] Bob ran but no new script file found.\n", stdout);
      return res.status(500).json({
        error: "Bob finished but no script file was written",
        bobOutput: stdout,
      });
    }

    const scriptFile = path.join(SCRIPTS_DIR, newFiles[0]);
    let script;
    try {
      script = JSON.parse(fs.readFileSync(scriptFile, "utf8"));
    } catch (parseErr) {
      return res.status(500).json({
        error: "Generated script is not valid JSON",
        file: scriptFile,
      });
    }

    // Basic schema validation
    if (!script.name || !Array.isArray(script.steps)) {
      return res.status(500).json({
        error: "Generated script is missing required fields (name, steps)",
        script,
      });
    }

    console.log(`[bob-bridge] Generated "${script.name}" (${script.steps.length} steps)`);
    return res.json(script);
  });
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`[bob-bridge] Listening on http://127.0.0.1:${PORT}`);
  console.log(`[bob-bridge] Workspace: ${WORKSPACE}`);
});
