#!/usr/bin/env node
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const EVENT_MAP = {
  SessionStart: "session_start",
  UserPromptSubmit: "agent_start",
  Stop: "agent_end",
  StopFailure: "agent_failed",
  SessionEnd: "session_shutdown",
};

function defaultStatusDir() {
  return join(tmpdir(), `pi-agent-status-${process.env.USER || "unknown"}`);
}

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
  });
}

function parseInput(text) {
  try {
    return JSON.parse(text || "{}");
  } catch {
    return undefined;
  }
}

function timestamp() {
  const fixed = process.env.CLAUDE_AGENT_STATUS_TEST_NOW;
  return fixed ? Number(fixed) : Date.now();
}

function eventPayload(input, event) {
  const payload = {
    ts: timestamp(),
    pid: process.pid,
    source: "claude-code",
    agentId: process.env.NVIM_AGENT_ID,
    event,
  };

  if (input.cwd) payload.cwd = input.cwd;
  if (input.session_id) payload.sessionId = input.session_id;
  if (input.prompt_id) payload.promptId = input.prompt_id;
  if (input.error_type) payload.errorType = input.error_type;

  return payload;
}

async function main() {
  const agentId = process.env.NVIM_AGENT_ID;
  if (!agentId) return;

  const input = parseInput(await readStdin());
  if (!input) return;

  const event = EVENT_MAP[input.hook_event_name];
  if (!event) return;

  const dir = process.env.NVIM_AGENT_STATUS_DIR || defaultStatusDir();
  mkdirSync(dir, { recursive: true });
  appendFileSync(join(dir, "events.jsonl"), JSON.stringify(eventPayload(input, event)) + "\n", "utf8");
}

main().catch((error) => {
  console.error(error?.message || String(error));
  process.exitCode = 0;
});
