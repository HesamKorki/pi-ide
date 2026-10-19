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
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="claude-code",cwd="/tmp/projects/pi-ide",ts=1791806400000}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.name == "claude/pi-ide@10-12" end, 50), "expected claude/pi-ide@10-12, got " .. tostring(tab.name))`,
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
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd="/tmp/projects/pi-ide",ts=1791806400000}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.name == "pi/pi-ide@10-12" end, 50), "expected pi/pi-ide@10-12, got " .. tostring(tab.name))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Neovim uses the original Pi session date and ignores prompt-based titles", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd="/tmp/projects/pi-ide/",sessionName=string.rep("first prompt ", 100),sessionStartedAt="2026-09-22T14:00:00.000Z",ts=1791806400000}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return tab.name == "pi/pi-ide@09-22" end, 50), "expected original session date, got " .. tostring(tab.name))
       assert(vim.api.nvim_buf_get_name(tab.buf):match("agent:pi/pi%-ide@09%-22$"), "expected buffer name to follow label")`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Pi labels stay short and update when switching sessions", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local s=_G.__pi_ide_state
       local tab=s.tabs[1]
       vim.fn.mkdir(vim.fn.fnamemodify(s.event_file, ":h"), "p")
       local function emit(cwd, date)
         local f=assert(io.open(s.event_file, "a"))
         f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd=cwd,sessionStartedAt=date}) .. "\\n")
         f:close()
       end
       emit("/tmp/projects/agentic-gateway-backend", "2026-09-22T14:00:00.000Z")
       assert(vim.wait(2500, function() return tab.name == "pi/agentic-gateway…@09-22" end, 50), "expected short basename, got " .. tostring(tab.name))
       emit("/tmp/projects/other", "2026-10-12T14:00:00.000Z")
       assert(vim.wait(2500, function() return tab.name == "pi/other@10-12" end, 50), "expected new session label")
       emit("/tmp/projects/ééééééééééééééééé", "2026-10-12T14:00:00.000Z")
       assert(vim.wait(2500, function() return tab.name == "pi/ééééééééééééééé…@10-12" end, 50), "must truncate characters, not UTF-8 bytes")`,
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
       f:write(vim.json.encode({agentId=tab.id,event="session_start",source="pi",cwd="/tmp/projects/pi-ide",sessionName="Session name"}) .. "\\n")
       f:write(vim.json.encode({agentId=tab.id,event="session_info_changed",source="pi",cwd="/tmp/projects/pi-ide",sessionName="Renamed session"}) .. "\\n")
       f:close()
       vim.wait(1500, function() return false end, 50)
       assert(tab.name == "backend", "expected backend to remain sticky, got " .. tostring(tab.name))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("AgentDelete removes the active agent and stops its terminal job", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local M=require("pi_ide")
       local s=_G.__pi_ide_state
       local before=#s.tabs
       M.new("victim", {"sh", "-c", "sleep 30"})
       local victim=s.tabs[s.active]
       local job=victim.job
       assert(job and job > 0, "expected active tab to store terminal job id")
       assert(vim.fn.jobwait({job}, 0)[1] == -1, "expected job to be running before delete")
       M.delete()
       assert(#s.tabs == before, "expected delete to remove one tab")
       for _, tab in ipairs(s.tabs) do
         assert(tab.id ~= victim.id, "deleted tab still present")
       end
       assert(vim.wait(2500, function() return vim.fn.jobwait({job}, 0)[1] ~= -1 end, 50), "expected delete to stop terminal job")
       assert(vim.api.nvim_get_commands({}).AgentDelete ~= nil, "expected :AgentDelete command")`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});

test("Agent ids stay unique after deleting a tab", async () => {
  await withTempDir(async (dir) => {
    const result = runNvim(
      `local M=require("pi_ide")
       local s=_G.__pi_ide_state
       M.new("second")
       M.new("third")
       M.delete(1)
       M.new("fourth")
       local seen={}
       for _, tab in ipairs(s.tabs) do
         assert(not seen[tab.id], "duplicate agent id " .. tab.id)
         seen[tab.id]=true
       end
       local second, fourth=s.tabs[1], s.tabs[3]
       local f=assert(io.open(s.event_file, "w"))
       f:write(vim.json.encode({agentId=fourth.id,event="agent_start"}) .. "\\n")
       f:close()
       assert(vim.wait(2500, function() return fourth.status == "running" end, 50), "expected new tab to receive its own events")
       assert(second.status == "idle", "expected other tabs to keep their status, got " .. tostring(second.status))`,
      { NVIM_AGENT_STATUS_DIR: dir }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
  });
});
