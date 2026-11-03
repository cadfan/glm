<#
.SYNOPSIS
  Launch Claude Code against Z.ai's GLM Coding Plan (Anthropic-compatible endpoint).

.USAGE
  glm                      start Claude Code on GLM, in the current directory
  glm -SetToken            store/replace the Z.ai Coding Plan key (prompted, hidden input)
  glm -Status              show endpoint + whether a token is stored, without launching
  glm -Model glm-5.3-flash pin a specific GLM model for all tiers (default: let Z.ai route)
  glm -Clean               use the slim ~/.claude-local profile (no MCP/plugins, far fewer tokens/turn)
  glm <claude args...>     anything else is passed straight to claude (e.g. glm -p "hi", glm --resume)

.NOTES
  Token is stored DPAPI-encrypted (tied to this Windows user) at ~/.config/glm/token.
  Endpoint per https://docs.z.ai/scenario-example/develop-tools/claude . Z.ai advise NOT
  hardcoding model names so the plan can route to its latest model; -Model overrides that.
#>
[CmdletBinding()]
param(
  [switch]$SetToken,
  [switch]$Status,
  [switch]$Clean,
  [string]$Model = "",
  [Parameter(ValueFromRemainingArguments)][string[]]$Rest
)

$BaseUrl   = "https://api.z.ai/api/anthropic"
$TokenDir  = Join-Path $HOME ".config\glm"
$TokenFile = Join-Path $TokenDir "token"

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
  Write-Host "model    : $(if ($Model) { $Model } else { '(Z.ai default routing)' })"
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
if ($Model) {
  $env:ANTHROPIC_MODEL                = $Model
  $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Model
  $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
  $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $Model
  $env:ANTHROPIC_DEFAULT_FABLE_MODEL  = $Model
  $env:CLAUDE_CODE_SUBAGENT_MODEL     = $Model
  if ($Model -like '*[[]1m[]]') { $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "1000000" }
}
if ($Clean) { $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-local" }

Write-Host "GLM via Z.ai  model=$(if ($Model) { $Model } else { 'default' })  profile=$(if ($Clean) { 'clean' } else { 'full' })" -ForegroundColor Cyan
claude @Rest
