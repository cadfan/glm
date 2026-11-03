# glm

Run [Claude Code](https://claude.com/claude-code) on Z.ai's GLM models from Windows Terminal with one command.

Type `glm` instead of `claude` and the session goes to Z.ai's Anthropic-compatible endpoint using your own GLM Coding Plan key. Your normal `claude` command is untouched.

## Install

Needs PowerShell 7 and Claude Code already installed (`irm https://claude.ai/install.ps1 | iex`).

```powershell
irm https://raw.githubusercontent.com/cadfan/glm/main/install.ps1 | iex
```

Or clone this repo and run `.\install.ps1`.

Then store your key once:

```powershell
glm -SetToken
```

Paste the key from your [Z.ai Coding Plan](https://z.ai/manage-apikey/apikey-list) page. It is a different key from a standard Z.ai API key, and the plan's quota only applies through this endpoint. The key is encrypted with Windows DPAPI, tied to your Windows account, and stored at `~/.config/glm/token`. Nothing goes in a dotfile in plain text.

## Use

```powershell
glm                          # Claude Code on GLM, in the current folder
glm -Status                  # endpoint, token present?, model, profile
glm -Model glm-5.3-flash[1m] # pin a model for every tier; [1m] = 1M context
glm -Clean                   # use ~/.claude-local (no MCP servers/plugins, cheaper turns)
glm --resume                 # anything else is passed straight to claude
```

By default no model is pinned. Z.ai recommend leaving it unset so the plan routes to its latest model (GLM-5.3 at the time of writing).

## How it works

`glm.ps1` sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` and `API_TIMEOUT_MS` for that one process and runs `claude`. `glm.cmd` is a shim so it also works from cmd.exe. Per the [Z.ai Claude Code docs](https://docs.z.ai/scenario-example/develop-tools/claude).

## Uninstall

Delete `~/.local/bin/glm.ps1`, `~/.local/bin/glm.cmd` and `~/.config/glm/`.
