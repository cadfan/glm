<#
.SYNOPSIS
  Launch Claude Code against Z.ai's GLM Coding Plan (Anthropic-compatible endpoint).

.USAGE
  glm                      start Claude Code on GLM, in the current directory
  glm -SetToken            store/replace the Z.ai Coding Plan key (prompted, hidden input)
  glm -Status              show endpoint + whether a token is stored, without launching
  glm -Model glm-5.3[1m]   pin one GLM model for all tiers (default: glm-5.3 big, glm-5.3-flash small)
  glm -Clean               use the slim ~/.claude-local profile (no MCP/plugins, far fewer tokens/turn)
  glm <claude args...>     anything else is passed straight to claude (e.g. glm -p "hi", glm --resume)

.NOTES
  Token is stored DPAPI-encrypted (tied to this Windows user) at ~/.config/glm/token.
  Endpoint per https://docs.z.ai/scenario-example/develop-tools/claude . Tiers map to GLM-5.3
  (opus/sonnet/fable) and GLM-5.3-Flash (haiku/subagents); a [1m] suffix on a model id unlocks
  the 1M window. Claude Code's /model picker keeps its Claude labels; the ids underneath are GLM.
#>

# Hand-parsed so claude's own flags (-p, --output-format, --resume ...) pass through untouched.
$SetToken = $false; $Status = $false; $Clean = $false; $Model = ""; $Rest = @()
for ($i = 0; $i -lt $args.Count; $i++) {
  switch -Regex ($args[$i]) {
    '^-SetToken$' { $SetToken = $true; continue }
    '^-Status$'   { $Status = $true; continue }
    '^-Clean$'    { $Clean = $true; continue }
    '^-Model$'    { $i++; $Model = "$($args[$i])"; continue }
    default       { $Rest += $args[$i] }
  }
}

$BaseUrl   = "https://api.z.ai/api/anthropic"
$TokenDir  = Join-Path $HOME ".config\glm"
$TokenFile = Join-Path $TokenDir "token"
$big   = if ($Model) { $Model } else { "glm-5.3" }        # 1M context, 128K output (Z.ai docs)
$small = if ($Model) { $Model } else { "glm-5.3-flash" }

function Save-GlmToken {
  $sec = Read-Host "Paste Z.ai Coding Plan API key" -AsSecureString
  if ($sec.Length -eq 0) { Write-Host "no key entered, nothing saved" -ForegroundColor Yellow; exit 1 }
  New-Item -ItemType Directory -Force $TokenDir | Out-Null
  $sec | ConvertFrom-SecureString | Set-Content -NoNewline $TokenFile
  Write-Host "token saved to $TokenFile (DPAPI, user-scoped)" -ForegroundColor Green
}

function Get-GlmToken {
  if (-not (Test-Path $TokenFile)) { return $null }
  $sec = Get-Content -Raw $TokenFile | ConvertTo-SecureString
  [System.Net.NetworkCredential]::new("", $sec).Password
}

if ($SetToken) { Save-GlmToken; exit 0 }

$token = Get-GlmToken

if ($Status) {
  Write-Host "endpoint : $BaseUrl"
  Write-Host "token    : $(if ($token) { 'stored (' + $token.Substring(0,[Math]::Min(6,$token.Length)) + '...)' } else { 'MISSING - run: glm -SetToken' })"
  Write-Host "model    : $big (opus/sonnet/fable), $small (haiku/subagents)"
  Write-Host "profile  : $(if ($Clean) { '~/.claude-local (clean)' } else { '~/.claude (full)' })"
  exit 0
}

if (-not $token) {
  Write-Host "No Z.ai token stored. Run:  glm -SetToken" -ForegroundColor Red
  exit 1
}

$env:ANTHROPIC_BASE_URL   = $BaseUrl
$env:ANTHROPIC_AUTH_TOKEN = $token
$env:API_TIMEOUT_MS       = "3000000"      # Z.ai recommendation; GLM can be slow on long turns

# Tier mapping: Claude Code's /model picker keeps its Opus/Sonnet/Haiku labels, but each tier
# resolves to the GLM id below. -Model <id> pins every tier to one model.
$env:ANTHROPIC_MODEL                = $big
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $big
$env:ANTHROPIC_DEFAULT_FABLE_MODEL  = $big
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $big
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $small
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $small

# Claude Code doesn't know GLM ids, so tell it the window instead of letting it guess.
if ($big -like '*[[]1m[]]') {
  $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS  = "1000000"
  $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "1000000"
} else {
  $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS  = "200000"
}

if ($Clean) { $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-local" }

Write-Host "GLM via Z.ai  model=$big/$small  profile=$(if ($Clean) { 'clean' } else { 'full' })" -ForegroundColor Cyan
claude @Rest
