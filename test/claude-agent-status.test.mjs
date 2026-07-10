import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const script = new URL("../scripts/claude-agent-status.mjs", import.meta.url);

async function withTempDir(fn) {
  const dir = await mkdtemp(join(tmpdir(), "pi-ide-claude-status-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function runHook(input, env) {
  return spawnSync(process.execPath, [script.pathname], {
    input: JSON.stringify(input),
    encoding: "utf8",
    env: {
      ...process.env,
      ...env,
      CLAUDE_AGENT_STATUS_TEST_NOW: "1234567890",
    },
  });
}

async function readEvents(dir) {
  const text = await readFile(join(dir, "events.jsonl"), "utf8");
  return text.trim().split("\n").map((line) => JSON.parse(line));
}

test("maps UserPromptSubmit to agent_start", async () => {
  await withTempDir(async (dir) => {
    const result = runHook(
      { hook_event_name: "UserPromptSubmit", cwd: "/repo", session_id: "s1", prompt_id: "p1" },
      { NVIM_AGENT_ID: "nvim-1", NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr);
    const events = await readEvents(dir);
    assert.deepEqual(events, [
      {
        ts: 1234567890,
        pid: events[0].pid,
        source: "claude-code",
        agentId: "nvim-1",
        event: "agent_start",
        cwd: "/repo",
        sessionId: "s1",
        promptId: "p1",
      },
    ]);
    assert.equal(typeof events[0].pid, "number");
  });
});

test("maps Stop to agent_end with a summary", async () => {
  await withTempDir(async (dir) => {
    const result = runHook(
      {
        hook_event_name: "Stop",
        cwd: "/repo",
        session_id: "s1",
        prompt_id: "p2",
        last_assistant_message: "Implemented the requested change.\n\nDetails follow.",
      },
      { NVIM_AGENT_ID: "nvim-2", NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr);
    const events = await readEvents(dir);
    assert.equal(events[0].event, "agent_end");
    assert.equal(events[0].summary, "Implemented the requested change.");
  });
});

test("maps StopFailure to agent_failed", async () => {
  await withTempDir(async (dir) => {
    const result = runHook(
      { hook_event_name: "StopFailure", cwd: "/repo", session_id: "s1", prompt_id: "p3", error_type: "rate_limit" },
      { NVIM_AGENT_ID: "nvim-3", NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr);
    const events = await readEvents(dir);
    assert.equal(events[0].event, "agent_failed");
    assert.equal(events[0].errorType, "rate_limit");
  });
});

test("does nothing when NVIM_AGENT_ID is missing", async () => {
  await withTempDir(async (dir) => {
    const result = runHook({ hook_event_name: "Stop" }, { NVIM_AGENT_STATUS_DIR: dir, NVIM_AGENT_ID: "" });

    assert.equal(result.status, 0, result.stderr);
    await assert.rejects(readFile(join(dir, "events.jsonl"), "utf8"), /ENOENT/);
  });
});

test("ignores malformed JSON without blocking Claude Code", async () => {
  await withTempDir(async (dir) => {
    const result = spawnSync(process.execPath, [script.pathname], {
      input: "not-json",
      encoding: "utf8",
      env: {
        ...process.env,
        NVIM_AGENT_ID: "nvim-3",
        NVIM_AGENT_STATUS_DIR: dir,
      },
    });

    assert.equal(result.status, 0, result.stderr);
    await assert.rejects(readFile(join(dir, "events.jsonl"), "utf8"), /ENOENT/);
  });
});
