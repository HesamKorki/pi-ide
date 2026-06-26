# pi-ide

A small Neovim workspace for running multiple [`pi`](https://pi.dev) agent shells while keeping normal development tools one keystroke away.

The premise is simple: the bottleneck in software development is increasingly **attention**. You may have several agents, test runs, and shell tasks moving at the same time, but constantly switching terminals makes it hard to know what needs your focus. `pi-ide` gives you a minimal control room: big interactive agent terminals, a compact status view, a scratch shell, and the usual file picker/editor workflow.

```text
┌──────────────────────────────────────────────┬────────────────────────────┐
│ main area                                    │ Agents                     │
│ active agent shell, or a file you are editing│ ▶ [1] backend  🤔 running  │
│                                              │   [2] tests    ✅ done     │
│                                              ├────────────────────────────┤
│                                              │ scratch shell              │
│                                              │ quick ad-hoc commands      │
└──────────────────────────────────────────────┴────────────────────────────┘
```

## What it does

- Opens a Neovim workspace with:
  - a large main area for the active agent shell or normal file editing
  - a compact agent/status panel
  - a small scratch terminal for ad-hoc commands
- Lets you run plain `zsh`/`bash` agent tabs and type `pi` yourself.
- Tracks `pi` lifecycle status automatically when `pi` runs inside a managed agent shell.
- Lets you switch agents by keymap or mouse click.
- Keeps file navigation/editing available through your existing Neovim setup.

Status icons:

| Icon | Meaning |
| --- | --- |
| 🟢 | idle / ready |
| 🤔 | pi agent is running |
| ✅ | pi agent finished its turn |
| 🛑 | shell stopped |
| ❌ | shell failed |
| ❔ | unknown |

## How status tracking works

`pi-ide` has two parts:

1. **Pi extension**: `extensions/nvim-agent-status.ts`
   - listens to Pi lifecycle events such as `agent_start` and `agent_end`
   - writes structured JSONL events to `/tmp/pi-agent-status-$USER/events.jsonl`
2. **Neovim plugin**: `lua/pi_ide/init.lua`
   - starts managed shell terminals with `NVIM_AGENT_ID`
   - watches the JSONL event file
   - updates the agent status panel

This avoids brittle prompt parsing. The status comes from Pi's own lifecycle events, not from guessing whether a terminal prompt returned.

## Requirements

- Neovim 0.10+
- `pi` installed
- A shell such as `zsh` or `bash`
- Optional but recommended: LazyVim / Snacks picker for `<leader>ff`

## Installation

You should install both halves from the same repository.

### 1. Install the Pi package

This installs the Pi extension so `pi` can emit lifecycle events for Neovim.

```bash
pi install git:github.com/HesamKorki/pi-ide
```

You can verify it is installed with:

```bash
pi list
```

> The package is discoverable by Pi's package gallery because `package.json` includes the `pi-package` keyword and a `pi.extensions` manifest.

### 2. Install the Neovim plugin

With `lazy.nvim`:

```lua
{
  "HesamKorki/pi-ide",
  config = function()
    require("pi_ide").setup()
  end,
}
```

Then restart Neovim or run `:Lazy sync`.

## Usage

Open the workspace:

```vim
:AgentWorkspace
```

The default agent tab is a normal shell. Type `pi` there when you want an agent session:

```bash
pi
```

When Pi starts processing a prompt, the tab becomes `🤔 running`. When the turn ends, it becomes `✅ done`.

### Commands

| Command | Description |
| --- | --- |
| `:AgentWorkspace` | Open/rebuild the workspace |
| `:AgentNew` | Create a new shell-backed agent tab |
| `:AgentNew name` | Create a new agent tab named `name` |
| `:AgentNew name command` | Create a tab running `command` |
| `:AgentSelect 2` | Switch main area to agent tab 2 |
| `:AgentRename name` | Rename the active agent tab |

Examples:

```vim
:AgentWorkspace
:AgentRename backend
:AgentNew tests
:AgentNew review zsh
:AgentSelect 1
```

### Keymaps

Default keymaps installed by `require("pi_ide").setup()`:

| Key | Action |
| --- | --- |
| `<leader>aw` | Open workspace |
| `<leader>aa` | Focus/show the active agent shell in the main area |
| `<leader>as` | Focus the scratch shell |
| `<leader>an` | New agent shell |
| `<leader>ar` | Rename active agent shell |
| `<leader>a1` ... `<leader>a9` | Switch to agent tab 1–9 |
| `<leader>ff` | Open file picker in the main area |

You can also click an agent row in the status panel to switch to it.

## File editing workflow

`pi-ide` is intentionally not a full IDE replacement. It tries to keep your normal Neovim workflow intact:

1. Use `:AgentWorkspace` to supervise agents.
2. Use `<leader>ff` to open files in the main area.
3. Edit as usual.
4. Press `<leader>aa` to return to the active agent shell.
5. Use the scratch shell for quick commands that should not pollute agent sessions.

## Limitations

- Automatic `running`/`done` status is for `pi` sessions running inside managed agent shells.
- Generic shell commands do not emit Pi lifecycle events; their terminal status only changes when the shell exits.
- The UI is intentionally minimal. It is not a replacement for tmux, terminal multiplexers, or full IDE project views.
- Emoji alignment depends on your terminal/font. If spacing looks odd, switch to a font with better emoji width support or patch the icons locally.

## Development

Clone the repo:

```bash
git clone git@github.com:HesamKorki/pi-ide.git
cd pi-ide
```

Try the Neovim plugin locally with Lazy:

```lua
{
  dir = "/path/to/pi-ide",
  config = function()
    require("pi_ide").setup()
  end,
}
```

Try the Pi extension without installing globally:

```bash
pi -e ./extensions/nvim-agent-status.ts
```

Or install the local package:

```bash
pi install /path/to/pi-ide
```

## Philosophy

`pi-ide` is built around one idea: agents do not remove the need for developer attention; they change where attention is spent. A useful interface should make concurrent agent work visible without forcing you out of your editor or hiding the boring but necessary tools: files, shells, tests, and quick commands.

So this project stays small:

- no heavy project model
- no custom agent protocol
- no terminal prompt scraping
- no attempt to replace your editor setup

Just enough structure to see what each agent is doing and get back to coding quickly.

## License

MIT
