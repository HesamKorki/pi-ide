local M = {}

local uv = vim.uv or vim.loop
local state = {
  tabs = {},
  active = 1,
  status_buf = nil,
  main_win = nil,
  status_win = nil,
  scratch_win = nil,
  scratch_buf = nil,
  timer = nil,
  event_file = "/tmp/pi-agent-status-" .. (vim.env.USER or "unknown") .. "/events.jsonl",
  event_pos = 0,
}

local icons = {
  idle = "🟢",
  running = "🤔",
  done = "✅",
  stopped = "🛑",
  failed = "❌",
  unknown = "❔",
}

local function status_dir()
  return "/tmp/pi-agent-status-" .. (vim.env.USER or "unknown")
end

local function ensure_status_buf()
  if state.status_buf and vim.api.nvim_buf_is_valid(state.status_buf) then
    return state.status_buf
  end
  state.status_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.status_buf].buftype = "nofile"
  vim.bo[state.status_buf].bufhidden = "hide"
  vim.bo[state.status_buf].swapfile = false
  vim.bo[state.status_buf].filetype = "agent-workspace"
  vim.api.nvim_buf_set_name(state.status_buf, "Agent Workspace")
  vim.keymap.set("n", "<LeftRelease>", function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local idx = line - 1
    if state.tabs[idx] then
      M.select(idx)
    end
  end, { buffer = state.status_buf, desc = "Select agent tab with mouse" })
  return state.status_buf
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
    table.insert(lines, string.format("%s [%d] %-12s %s %s%s", current, i, tab.name, icon, tab.status, elapsed))
  end
  if #state.tabs == 0 then
    table.insert(lines, "  <leader>an new")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if state.status_win and vim.api.nvim_win_is_valid(state.status_win) then
    vim.api.nvim_win_set_height(state.status_win, math.min(6, math.max(3, #lines)))
  end
end

local function active_tab()
  return state.tabs[state.active]
end

function M.focus_agent()
  local tab = active_tab()
  if not tab then
    M.new()
    tab = active_tab()
  end
  if not (state.main_win and vim.api.nvim_win_is_valid(state.main_win)) then
    state.main_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(state.main_win)
  vim.api.nvim_win_set_buf(state.main_win, tab.buf)
  if vim.bo[tab.buf].buftype == "terminal" then
    vim.cmd("startinsert")
  end
end

function M.focus_scratch()
  if state.scratch_win and vim.api.nvim_win_is_valid(state.scratch_win) then
    vim.api.nvim_set_current_win(state.scratch_win)
    if state.scratch_buf and vim.bo[state.scratch_buf].buftype == "terminal" then
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
  elseif ev.event == "agent_end" then
    tab.status = "done"
    tab.started_at = nil
    tab.summary = ev.summary
  elseif ev.event == "session_shutdown" then
    tab.status = "stopped"
    tab.started_at = nil
  elseif ev.event == "session_start" then
    tab.status = "idle"
  end
  render_status()
end

local function poll_events()
  local fd = io.open(state.event_file, "r")
  if not fd then
    return
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

local function create_terminal_buffer(name, cmd, id)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
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

function M.new(name, cmd)
  name = name and name ~= "" and name or ("shell-" .. (#state.tabs + 1))
  cmd = cmd and cmd ~= "" and cmd or (vim.o.shell or "bash")
  local id = string.format("nvim-%d-%d", uv.os_getpid(), #state.tabs + 1)

  if not (state.main_win and vim.api.nvim_win_is_valid(state.main_win)) then
    state.main_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(state.main_win)
  local buf = create_terminal_buffer("agent:" .. name, cmd, id)

  table.insert(state.tabs, { id = id, name = name, cmd = cmd, buf = buf, status = "idle" })
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
  if state.scratch_buf and vim.api.nvim_buf_is_valid(state.scratch_buf) then
    return
  end
  if not (state.scratch_win and vim.api.nvim_win_is_valid(state.scratch_win)) then
    return
  end
  vim.api.nvim_set_current_win(state.scratch_win)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, "agent:scratch")
  vim.api.nvim_win_set_buf(state.scratch_win, buf)
  vim.fn.termopen(vim.o.shell or "bash")
  state.scratch_buf = buf
end

function M.open()
  start_timer()

  -- Build the workspace from a single full-height main window. Without this,
  -- invoking AgentWorkspace from an existing split can leave the active agent
  -- terminal trapped in a short top pane with unused space below.
  if #vim.api.nvim_list_wins() > 1 then
    vim.cmd("only")
  end
  state.main_win = vim.api.nvim_get_current_win()

  vim.cmd("botright vertical 44new")
  state.status_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.status_win, ensure_status_buf())
  vim.wo[state.status_win].number = false
  vim.wo[state.status_win].relativenumber = false
  vim.wo[state.status_win].signcolumn = "no"
  vim.api.nvim_win_set_height(state.status_win, 4)

  vim.cmd("belowright split")
  state.scratch_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.scratch_win, 10)
  ensure_scratch()

  if #state.tabs == 0 then
    M.new("shell", vim.o.shell or "bash")
  else
    M.focus_agent()
  end

  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    pcall(vim.api.nvim_win_set_height, state.main_win, 999)
  end
  render_status()
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

  vim.keymap.set("n", "<leader>aw", M.open, { desc = "Agent workspace" })
  vim.keymap.set("n", "<leader>aa", M.focus_agent, { desc = "Focus active agent" })
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

  -- In the agent workspace, file finding should open files in the main area,
  -- even if focus is currently in the scratch terminal or status pane.
  vim.keymap.set("n", "<leader>ff", function()
    if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
      vim.api.nvim_set_current_win(state.main_win)
    end
    if Snacks and Snacks.picker then
      Snacks.picker.files()
    else
      vim.cmd("edit .")
    end
  end, { desc = "Find files in main area" })
end

return M
