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
glm -Status                  # version, endpoint, token present?, models, profile (no launch)
glm -Model glm-5.3           # pin one model for every tier
glm -Window 200K             # context window Claude Code works to (default 1M)
glm -Clean                   # use ~/.claude-local (no MCP servers/plugins, cheaper turns)
glm -Update                  # check GitHub now, install a newer glm if there is one
glm -NoUpdate                # skip the hourly update check for this launch
glm -Version                 # print the version
glm --resume                 # anything else is passed straight to claude
```

By default the Claude tiers map to GLM models: Opus/Sonnet use `glm-5.3`, Haiku and subagents use `glm-5.3-flash`. Both are 1M context, 128K output on Z.ai's side, and Claude Code is told a 1M window by default. Claude Code would otherwise assume 200K for an id it does not recognise and compact far too early. `-Window` shrinks it if you want shorter, cheaper sessions.

### The `/model` picker

Inside Claude Code, `/model` shows the GLM models by name with their context and output sizes, not the stock Opus/Sonnet/Haiku rows. That comes from a `modelPicker` block the launcher writes to `~/.config/glm/settings.json` and passes with `--settings`, so your own `~/.claude/settings.json` is never touched. If you pass your own `--settings`, the curated picker is skipped. Prices shown in the picker are Anthropic list prices and mean nothing here; billing is your Z.ai plan.

### Upgrading an older install

If your copy predates 0.1.0 it has no updater, so run the install one-liner again. It overwrites `glm.ps1` and `glm.cmd` and leaves your stored token alone:

```powershell
irm https://raw.githubusercontent.com/cadfan/glm/main/install.ps1 | iex
```

Check with `glm -Version`. That is the last time you need to do it by hand.

### Updates

Once an hour at most, before launching, `glm` reads the version line of `glm.ps1` on GitHub. If it is newer, it downloads `glm.ps1` and `glm.cmd`, checks the new script parses, keeps the old one as `glm.ps1.bak`, and carries on with the new version. `glm -Update` forces the check. `glm -NoUpdate` skips it for one launch. Set `GLM_NO_UPDATE=1` to turn it off entirely, for scripts. The check uses a 5-second timeout and goes silent when offline.

## How it works

`glm.ps1` sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `API_TIMEOUT_MS`, the per-tier `ANTHROPIC_DEFAULT_*_MODEL` ids and display names, and the context window for that one process, writes the picker settings, then runs `claude --settings <picker> <your args>`. `glm.cmd` is a shim so it also works from cmd.exe. Per the [Z.ai Claude Code docs](https://docs.z.ai/scenario-example/develop-tools/claude).

## Uninstall

Delete `~/.local/bin/glm.ps1`, `~/.local/bin/glm.cmd` (and `glm.ps1.bak` if present) and `~/.config/glm/`.
