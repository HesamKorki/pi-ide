import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import install from "../extensions/nvim-agent-status.ts";

async function withExtension(fn, agentId = "test-agent") {
  const dir = mkdtempSync(join(tmpdir(), "pi-ide-pi-status-"));
  const previous = {
    NVIM_AGENT_ID: process.env.NVIM_AGENT_ID,
    NVIM_AGENT_STATUS_DIR: process.env.NVIM_AGENT_STATUS_DIR,
  };
  process.env.NVIM_AGENT_STATUS_DIR = dir;
  if (agentId) process.env.NVIM_AGENT_ID = agentId;
  else delete process.env.NVIM_AGENT_ID;
  const handlers = new Map();
  install({ on: (event, handler) => handlers.set(event, handler) });
  try {
    await fn({
      dispatch: async (timestamp) => {
        await handlers.get("session_start")({}, {
          cwd: "/tmp/projects/pi-ide",
          sessionManager: { getHeader: () => timestamp ? { timestamp } : null },
        });
      },
      events: () => readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n").map(JSON.parse),
      eventFile: join(dir, "events.jsonl"),
    });
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(dir, { recursive: true, force: true });
  }
}

test("Pi extension emits original session timestamps on startup and session replacement", async () => {
  await withExtension(async ({ dispatch, events }) => {
    for (const date of ["2026-09-22T14:00:00.000Z", "2026-10-12T14:00:00.000Z", undefined]) {
      await dispatch(date);
    }
    assert.deepEqual(events().map(({ event, source, cwd, sessionStartedAt, agentId }) =>
      ({ event, source, cwd, sessionStartedAt, agentId })),
    ["2026-09-22T14:00:00.000Z", "2026-10-12T14:00:00.000Z", undefined].map((sessionStartedAt) => ({
      event: "session_start", source: "pi", cwd: "/tmp/projects/pi-ide", sessionStartedAt, agentId: "test-agent",
    })));
    assert.ok(events().every((event) => !("sessionName" in event)), "must not send prompt-based names");
  });
});

test("Pi extension does not write events outside managed terminals", async () => {
  await withExtension(async ({ dispatch, eventFile }) => {
    await dispatch("2026-10-12T14:00:00.000Z");
    assert.equal(existsSync(eventFile), false);
  }, null);
});
