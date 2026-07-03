import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

async function withTempDir(fn) {
  const dir = await mkdtemp(join(tmpdir(), "pi-ide-nvim-status-"));
  try {
    return await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function runNvim(lua, env = {}) {
  const checkedLua = `local ok, err = pcall(function() ${lua} end); if not ok then print(err); vim.cmd("cquit 1") end`;
  return spawnSync(
    "nvim",
    [
      "--headless",
      "+set runtimepath^=.",
      '+lua require("pi_ide").setup()',
      "+AgentWorkspace",
      `+lua ${checkedLua}`,
      "+qa",
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        ...env,
      },
    }
  );
}

test("Neovim status reader uses NVIM_AGENT_STATUS_DIR when provided", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      'local s=_G.__pi_ide_state; local expected=vim.env.NVIM_AGENT_STATUS_DIR .. "/events.jsonl"; assert(s.event_file == expected, "expected " .. expected .. ", got " .. tostring(s.event_file))',
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Neovim status reader recovers when the event file is truncated", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="agent_start",padding=string.rep("x", 2048)}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.status == "running" end, 50), "expected first event to set running, got " .. tostring(tab.status))
       f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="agent_end"}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.status == "done" end, 50), "expected truncated file event to set done, got " .. tostring(tab.status))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Neovim auto-names Claude tabs from provider and working directory", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="claude-code",cwd="/tmp/projects/pi-ide"}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.name == "claude/pi-ide" end, 50), "expected claude/pi-ide, got " .. tostring(tab.name))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Neovim auto-names Pi tabs from provider and working directory", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd="/tmp/projects/pi-ide"}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.name == "pi/pi-ide" end, 50), "expected pi/pi-ide, got " .. tostring(tab.name))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Manual tab names are not overwritten by agent session events", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       require("pi_ide").rename("backend")
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd="/tmp/projects/pi-ide"}) .. "\\n")
       f:close()
       vim.wait(1500, function() return false end, 50)
       assert(tab.name == "backend", "expected backend to remain sticky, got " .. tostring(tab.name))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});
