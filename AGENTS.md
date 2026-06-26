# AGENTS.md — pi-ide

Guidance for future agents working in this repository.

## Project shape

This repo is intentionally both:

1. a Pi package, via `package.json` + `pi.extensions`
2. a Neovim plugin, via `lua/pi_ide/init.lua`

Keep both install paths working.

## Pi package gallery / publishing

`pi.dev/packages` indexes Pi packages published to npm. GitHub installs work with `pi install git:github.com/HesamKorki/pi-ide`, but public gallery visibility requires an npm release.

Before publishing, verify `package.json` has:

- `keywords` including `pi-package`
- `pi.extensions` pointing at `./extensions`
- `files` including `README.md`, `LICENSE`, `extensions`, and `lua`

Verification commands:

```bash
node -e 'const p=require("./package.json"); if(!p.keywords.includes("pi-package")) throw new Error("missing pi-package"); if(!p.pi?.extensions?.length) throw new Error("missing pi extensions"); console.log("pi package metadata ok")'
npm pack --dry-run
```

Publishing steps, when the human explicitly asks for a release:

```bash
npm adduser
npm publish
```

After npm publishing, users can install the Pi extension with:

```bash
pi install npm:@hesamkorki/pi-ide
```

## Git policy

Never run `git push` unless the user's latest prompt explicitly asks to push.

## Manual verification

Neovim plugin smoke test:

```bash
nvim --headless +'set runtimepath^=/path/to/pi-ide' +'lua require("pi_ide").setup()' +'AgentWorkspace' +'lua local counts={terminal=0,nofile=0}; for _,w in ipairs(vim.api.nvim_list_wins()) do local b=vim.api.nvim_win_get_buf(w); counts[vim.bo[b].buftype]=(counts[vim.bo[b].buftype] or 0)+1 end; assert(counts.terminal>=2, "expected agent + scratch terminals"); assert(counts.nofile>=1, "expected status buffer")' +qa
```

Pi extension behavior depends on Pi lifecycle events and is best checked by installing locally, opening `:AgentWorkspace`, typing `pi` in an agent shell, and confirming status transitions from running to done.
