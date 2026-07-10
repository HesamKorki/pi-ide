local M = {}

local uv = vim.uv or vim.loop

local function status_dir()
  return vim.env.NVIM_AGENT_STATUS_DIR or ("/tmp/pi-agent-status-" .. (vim.env.USER or "unknown"))
end

local state = _G.__pi_ide_state or {
  tabs = {},
  active = 1,
  status_buf = nil,
  main_win = nil,
  status_win = nil,
  scratch_win = nil,
  scratch_buf = nil,
  timer = nil,
  event_file = status_dir() .. "/events.jsonl",
  event_pos = 0,
}
_G.__pi_ide_state = state

local icons = {
  idle = "🟢",
  running = "🤔",
  done = "✅",
  stopped = "🛑",
  failed = "❌",
  unknown = "❔",
}

local function win_valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local install_workspace_buffer_keymaps

local function mark_buf_role(buf, role)
  if buf_valid(buf) then
    vim.b[buf].pi_ide_role = role
    if role == "agent" or role == "scratch" or role == "status" then
      install_workspace_buffer_keymaps(buf)
    end
  end
end

local function mark_win_role(win, role)
  if win_valid(win) then
    vim.w[win].pi_ide_role = role
    -- Snacks picker honors snacks_main as a preferred target. Keep that tag
    -- exclusively on pi-ide's main pane so status/scratch stay sticky panes.
    vim.w[win].snacks_main = role == "main"
  end
end

local function buf_role(buf)
  return buf_valid(buf) and vim.b[buf].pi_ide_role or nil
end

local function win_role(win)
  return win_valid(win) and vim.w[win].pi_ide_role or nil
end

function install_workspace_buffer_keymaps(buf)
  if not buf_valid(buf) then
    return
  end

  vim.keymap.set({ "n", "t" }, "<leader>ff", function()
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "t" then
      vim.cmd("stopinsert")
    end
    M.find_files()
  end, { buffer = buf, desc = "Find files in pi-ide main area" })

  vim.keymap.set({ "n", "t" }, "<leader>ag", function()
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "t" then
      vim.cmd("stopinsert")
    end
    M.go_agent()
  end, { buffer = buf, desc = "Go to active agent" })

  vim.keymap.set({ "n", "t" }, "<leader>aa", function()
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "t" then
      vim.cmd("stopinsert")
    end
    M.go_agent()
  end, { buffer = buf, desc = "Focus active agent" })
end

local function is_status_buf(buf)
  if not buf_valid(buf) then
    return false
  end
  if buf == state.status_buf or buf_role(buf) == "status" then
    return true
  end
  return vim.bo[buf].filetype == "agent-workspace" or vim.api.nvim_buf_get_name(buf):match("Agent Workspace$") ~= nil
end

local function is_scratch_buf(buf)
  return buf_valid(buf) and (buf == state.scratch_buf or buf_role(buf) == "scratch")
end

local function is_managed_side_win(win)
  if not win_valid(win) then
    return false
  end
  local role = win_role(win)
  if role == "status" or role == "scratch" then
    return true
  end
  if win == state.status_win or win == state.scratch_win then
    return true
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return is_status_buf(buf) or is_scratch_buf(buf)
end

local function find_window_showing_buf(buf)
  if not buf_valid(buf) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return nil
end

local function find_unmanaged_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not is_managed_side_win(win) then
      return win
    end
  end
  return nil
end

local function ensure_status_buf()
  if state.status_buf and vim.api.nvim_buf_is_valid(state.status_buf) then
    mark_buf_role(state.status_buf, "status")
    return state.status_buf
  end
  state.status_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.status_buf].buftype = "nofile"
  vim.bo[state.status_buf].bufhidden = "hide"
  vim.bo[state.status_buf].swapfile = false
  vim.bo[state.status_buf].filetype = "agent-workspace"
  vim.api.nvim_buf_set_name(state.status_buf, "Agent Workspace")
  mark_buf_role(state.status_buf, "status")
  vim.keymap.set("n", "<LeftRelease>", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local idx = line - 1
    if state.tabs[idx] then
      M.select(idx)
    end
  end, { buffer = state.status_buf, desc = "Select agent tab with mouse" })
  return state.status_buf
end

local function compact_summary(summary)
  if not summary or summary == "" then
    return ""
  end
  summary = summary:gsub("%s+", " ")
  if #summary > 60 then
    summary = summary:sub(1, 57) .. "..."
  end
  return " · " .. summary
end

local function render_status()
  local buf = ensure_status_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = { "Agents" }
  for i, tab in ipairs(state.tabs) do
    local current = i == state.active and "▶" or " "
    local icon = icons[tab.status] or icons.unknown
    local elapsed = ""
    if tab.status == "running" and tab.started_at then
      elapsed = string.format(" %ds", math.floor((uv.now() - tab.started_at) / 1000))
    end
    table.insert(lines, string.format("%s [%d] %-12s %s %s%s%s", current, i, tab.name, icon, tab.status, elapsed, compact_summary(tab.summary)))
  end
  if #state.tabs == 0 then
    table.insert(lines, "  <leader>an new")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if win_valid(state.status_win) then
    vim.api.nvim_win_set_height(state.status_win, math.min(6, math.max(3, #lines)))
  end
end

local function active_tab()
  return state.tabs[state.active]
end

local function provider_label(source)
  if source == "claude-code" then
    return "claude"
  end
  if source == "pi" or source == nil then
    return "pi"
  end
  return nil
end

local function cwd_basename(cwd)
  if not cwd or cwd == "" then
    return nil
  end
  local normalized = cwd:gsub("/+$", "")
  local name = normalized:match("([^/]+)$")
  return name and name ~= "" and name or nil
end

local function auto_name_tab(tab, ev)
  if tab.manual_name then
    return
  end
  local provider = provider_label(ev.source)
  local dir = cwd_basename(ev.cwd)
  if not provider or not dir then
    return
  end
  tab.name = provider .. "/" .. dir
  if buf_valid(tab.buf) then
    pcall(vim.api.nvim_buf_set_name, tab.buf, "agent:" .. tab.name)
  end
end

local function ensure_main_win(preferred_buf)
  -- Keep the side panes as side panes. If the main window was closed while
  -- editing a file, do not silently reuse the focused status/scratch pane as
  -- the main area; create/recover a real main window instead.
  if win_valid(state.main_win) and not is_managed_side_win(state.main_win) then
    mark_win_role(state.main_win, "main")
    return state.main_win
  end

  local existing = find_window_showing_buf(preferred_buf)
  if existing and not is_managed_side_win(existing) then
    state.main_win = existing
    mark_win_role(existing, "main")
    return existing
  end

  local current = vim.api.nvim_get_current_win()
  if current and not is_managed_side_win(current) then
    state.main_win = current
    mark_win_role(current, "main")
    return current
  end

  local unmanaged = find_unmanaged_window()
  if unmanaged then
    state.main_win = unmanaged
    mark_win_role(unmanaged, "main")
    return unmanaged
  end

  -- Only managed panes remain. Split off a new window that can safely become
  -- the main area without overwriting the status or scratch windows.
  vim.cmd("topleft vertical new")
  state.main_win = vim.api.nvim_get_current_win()
  mark_win_role(state.main_win, "main")
  return state.main_win
end

function M.focus_agent()
  local tab = active_tab()
  if not tab then
    M.new()
    tab = active_tab()
  end
  if not tab or not buf_valid(tab.buf) then
    vim.notify("No valid active agent buffer", vim.log.levels.WARN)
    return
  end

  local main_win = ensure_main_win(tab.buf)
  vim.api.nvim_set_current_win(main_win)
  vim.api.nvim_win_set_buf(main_win, tab.buf)
  mark_win_role(main_win, "main")
  mark_buf_role(tab.buf, "agent")
  if vim.bo[tab.buf].buftype == "terminal" then
    vim.cmd("startinsert")
  end
end

function M.focus_scratch()
  if win_valid(state.scratch_win) then
    vim.api.nvim_set_current_win(state.scratch_win)
    if buf_valid(state.scratch_buf) and vim.bo[state.scratch_buf].buftype == "terminal" then
      vim.cmd("startinsert")
    end
  end
end

function M.select(idx)
  idx = tonumber(idx) or state.active
  if not state.tabs[idx] then
    vim.notify("No agent tab " .. tostring(idx), vim.log.levels.WARN)
    return
  end
  state.active = idx
  render_status()
  M.focus_agent()
end

local function handle_event(ev)
  local idx
  for i, tab in ipairs(state.tabs) do
    if tab.id == ev.agentId then
      idx = i
      break
    end
  end
  if not idx then
    return
  end
  local tab = state.tabs[idx]
  if ev.event == "agent_start" then
    tab.status = "running"
    tab.started_at = uv.now()
    tab.summary = nil
  elseif ev.event == "agent_end" then
    tab.status = "done"
    tab.started_at = nil
    tab.summary = ev.summary
  elseif ev.event == "agent_failed" then
    tab.status = "failed"
    tab.started_at = nil
    tab.summary = ev.summary
  elseif ev.event == "session_shutdown" then
    tab.status = "stopped"
    tab.started_at = nil
  elseif ev.event == "session_start" then
    tab.status = "idle"
    auto_name_tab(tab, ev)
  end
  render_status()
end

local function poll_events()
  local fd = io.open(state.event_file, "r")
  if not fd then
    return
  end
  local size = fd:seek("end") or 0
  if state.event_pos > size then
    state.event_pos = 0
  end
  fd:seek("set", state.event_pos)
  for line in fd:lines() do
    local ok, ev = pcall(vim.json.decode, line)
    if ok and ev and ev.agentId then
      handle_event(ev)
    end
  end
  state.event_pos = fd:seek()
  fd:close()
end

local function start_timer()
  if state.timer then
    return
  end
  state.timer = uv.new_timer()
  state.timer:start(250, 1000, vim.schedule_wrap(function()
    poll_events()
    render_status()
  end))
end

local function create_terminal_buffer(name, cmd, id, role)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
  mark_buf_role(buf, role or "agent")
  vim.api.nvim_set_current_buf(buf)
  vim.fn.termopen(cmd, {
    env = {
      NVIM_AGENT_ID = id,
      NVIM_AGENT_STATUS_DIR = status_dir(),
    },
    on_exit = function(_, code)
      for _, tab in ipairs(state.tabs) do
        if tab.id == id and tab.status ~= "done" then
          tab.status = code == 0 and "stopped" or "failed"
          tab.started_at = nil
        end
      end
      vim.schedule(render_status)
    end,
  })
  return buf
end

function M.new(name, cmd, opts)
  local manual_name = opts and opts.manual_name
  if manual_name == nil then
    manual_name = name ~= nil and name ~= ""
  end
  name = name and name ~= "" and name or ("shell-" .. (#state.tabs + 1))
  cmd = cmd and cmd ~= "" and cmd or (vim.o.shell or "bash")
  local id = string.format("nvim-%d-%d", uv.os_getpid(), #state.tabs + 1)

  ensure_main_win()
  vim.api.nvim_set_current_win(state.main_win)
  local buf = create_terminal_buffer("agent:" .. name, cmd, id, "agent")

  table.insert(state.tabs, { id = id, name = name, cmd = cmd, buf = buf, status = "idle", manual_name = manual_name })
  state.active = #state.tabs
  render_status()
  M.focus_agent()
end

function M.rename(name)
  local tab = active_tab()
  if not tab then
    vim.notify("No active agent tab", vim.log.levels.WARN)
    return
  end
  local function apply(new_name)
    if not new_name or new_name == "" then
      return
    end
    tab.name = new_name
    tab.manual_name = true
    if vim.api.nvim_buf_is_valid(tab.buf) then
      pcall(vim.api.nvim_buf_set_name, tab.buf, "agent:" .. new_name)
    end
    render_status()
  end
  if name and name ~= "" then
    apply(name)
  else
    vim.ui.input({ prompt = "Agent name: ", default = tab.name }, apply)
  end
end

local function ensure_scratch()
  if not win_valid(state.scratch_win) then
    return
  end
  if buf_valid(state.scratch_buf) then
    mark_buf_role(state.scratch_buf, "scratch")
    vim.api.nvim_win_set_buf(state.scratch_win, state.scratch_buf)
    return
  end

  vim.api.nvim_set_current_win(state.scratch_win)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "agent:scratch")
  mark_buf_role(buf, "scratch")
  vim.api.nvim_win_set_buf(state.scratch_win, buf)
  vim.fn.termopen(vim.o.shell or "bash")
  state.scratch_buf = buf
end

local function adopt_existing_workspace()
  -- Hot-reload safety: if this module was reloaded while an older workspace was
  -- already open, the old Lua-local state is gone but the terminal/status
  -- buffers still exist. Recover the obvious pieces before rebuilding.
  if #state.tabs > 0 then
    return
  end

  local terminals = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then
      table.insert(terminals, { win = win, buf = buf, width = vim.api.nvim_win_get_width(win) })
    elseif is_status_buf(buf) then
      state.status_win = win
      state.status_buf = buf
      mark_win_role(win, "status")
      mark_buf_role(buf, "status")
    end
  end

  table.sort(terminals, function(a, b)
    return a.width > b.width
  end)

  if terminals[1] then
    local agent = terminals[1]
    state.main_win = agent.win
    mark_win_role(agent.win, "main")
    mark_buf_role(agent.buf, "agent")
    table.insert(state.tabs, {
      id = "adopted-" .. tostring(agent.buf),
      name = "shell",
      cmd = vim.o.shell or "bash",
      buf = agent.buf,
      status = "idle",
    })
    state.active = 1
  end

  if terminals[2] then
    local scratch = terminals[2]
    state.scratch_win = scratch.win
    state.scratch_buf = scratch.buf
    mark_win_role(scratch.win, "scratch")
    mark_buf_role(scratch.buf, "scratch")
  end
end

local function prepare_workspace_main()
  local tab = active_tab()
  local preferred_buf = tab and buf_valid(tab.buf) and tab.buf or nil

  local main_win = ensure_main_win(preferred_buf)
  vim.api.nvim_set_current_win(main_win)
  if preferred_buf then
    vim.api.nvim_win_set_buf(main_win, preferred_buf)
  end

  -- Collapse any broken/partial layout, preserving the selected main window.
  if #vim.api.nvim_list_wins() > 1 then
    vim.cmd("only")
  end

  state.main_win = vim.api.nvim_get_current_win()
  mark_win_role(state.main_win, "main")
  state.status_win = nil
  state.scratch_win = nil
end

function M.open()
  start_timer()
  adopt_existing_workspace()

  -- Build the workspace from a single full-height real main window. If the
  -- user closed the file/agent main window and focus fell into a side pane,
  -- recover the active agent buffer first so :only doesn't preserve an old
  -- status/scratch pane as the new main area.
  prepare_workspace_main()

  vim.cmd("botright vertical 44new")
  state.status_win = vim.api.nvim_get_current_win()
  mark_win_role(state.status_win, "status")
  vim.api.nvim_win_set_buf(state.status_win, ensure_status_buf())
  vim.wo[state.status_win].number = false
  vim.wo[state.status_win].relativenumber = false
  vim.wo[state.status_win].signcolumn = "no"
  vim.api.nvim_win_set_height(state.status_win, 4)

  vim.cmd("belowright split")
  state.scratch_win = vim.api.nvim_get_current_win()
  mark_win_role(state.scratch_win, "scratch")
  vim.api.nvim_win_set_height(state.scratch_win, 10)
  ensure_scratch()

  if #state.tabs == 0 then
    M.new("shell", vim.o.shell or "bash", { manual_name = false })
  else
    M.focus_agent()
  end

  if win_valid(state.main_win) then
    pcall(vim.api.nvim_win_set_height, state.main_win, 999)
  end
  render_status()
end

local function layout_intact()
  return win_valid(state.main_win) and win_valid(state.status_win) and win_valid(state.scratch_win)
end

function M.go_agent()
  -- User-facing recovery/focus action. If the workspace chrome disappeared
  -- (for example after closing the main file window, or after the old bad
  -- <leader>ag created a single full-page terminal), rebuild the full layout.
  if layout_intact() then
    M.focus_agent()
  else
    M.open()
  end
end

function M.find_files()
  local tab = active_tab()
  local preferred_buf = tab and buf_valid(tab.buf) and tab.buf or nil
  vim.api.nvim_set_current_win(ensure_main_win(preferred_buf))

  if Snacks and Snacks.picker then
    Snacks.picker.files({
      main = {
        current = true,
        file = false,
      },
      jump = {
        close = true,
      },
    })
  else
    vim.cmd("edit .")
  end
end

local function install_keymaps()
  vim.keymap.set("n", "<leader>aw", M.open, { desc = "Agent workspace" })
  vim.keymap.set("n", "<leader>aa", M.go_agent, { desc = "Focus active agent" })
  vim.keymap.set("n", "<leader>ag", M.go_agent, { desc = "Go to active agent" })
  vim.keymap.set("n", "<leader>as", M.focus_scratch, { desc = "Focus scratch shell" })
  vim.keymap.set("n", "<leader>ar", function()
    M.rename()
  end, { desc = "Rename active agent" })
  for i = 1, 9 do
    vim.keymap.set("n", "<leader>a" .. i, function()
      M.select(i)
    end, { desc = "Agent " .. i })
  end
  vim.keymap.set("n", "<leader>an", function()
    M.new()
  end, { desc = "New agent terminal" })

  -- Override LazyVim/Snacks' global <leader>ff so file selection always starts
  -- from the pi-ide main pane, not whichever side terminal/status pane has focus.
  vim.keymap.set("n", "<leader>ff", M.find_files, { desc = "Find files in pi-ide main area" })
end

local function refresh_workspace_buffer_keymaps()
  if buf_valid(state.status_buf) then
    mark_buf_role(state.status_buf, "status")
  end
  if buf_valid(state.scratch_buf) then
    mark_buf_role(state.scratch_buf, "scratch")
  end
  for _, tab in ipairs(state.tabs) do
    if buf_valid(tab.buf) then
      mark_buf_role(tab.buf, "agent")
    end
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_status_buf(buf) then
      mark_win_role(win, "status")
      mark_buf_role(buf, "status")
    elseif is_scratch_buf(buf) then
      mark_win_role(win, "scratch")
      mark_buf_role(buf, "scratch")
    elseif buf_role(buf) == "agent" then
      mark_buf_role(buf, "agent")
    end
  end
end

function M.run(args)
  M.open()
  if args and args ~= "" then
    local name, cmd = args:match("^(%S+)%s+(.+)$")
    if cmd then
      M.new(name, cmd)
    else
      M.new(args, vim.o.shell or "bash")
    end
  end
end

function M.setup()
  refresh_workspace_buffer_keymaps()

  local group = vim.api.nvim_create_augroup("PiIdeWorkspace", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      if closed == state.main_win then
        state.main_win = nil
      end
      if closed == state.status_win then
        state.status_win = nil
      end
      if closed == state.scratch_win then
        state.scratch_win = nil
      end
    end,
  })

  vim.api.nvim_create_user_command("AgentWorkspace", function(opts)
    M.run(opts.args)
  end, { nargs = "*", complete = "shellcmd", force = true })
  vim.api.nvim_create_user_command("AgentNew", function(opts)
    local name, cmd = opts.args:match("^(%S+)%s+(.+)$")
    M.new(name or opts.args, cmd or (vim.o.shell or "bash"))
  end, { nargs = "*", complete = "shellcmd", force = true })
  vim.api.nvim_create_user_command("AgentSelect", function(opts)
    M.select(opts.args)
  end, { nargs = 1, force = true })
  vim.api.nvim_create_user_command("AgentRename", function(opts)
    M.rename(opts.args)
  end, { nargs = "?", force = true })

  install_keymaps()

  -- LazyVim/Snacks may register its own <leader>ff after this config file is
  -- sourced. Re-apply pi-ide keymaps once the lazy startup wave has settled.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VeryLazy",
    callback = function()
      vim.schedule(install_keymaps)
      vim.defer_fn(install_keymaps, 100)
    end,
  })
  vim.schedule(install_keymaps)
end

return M
