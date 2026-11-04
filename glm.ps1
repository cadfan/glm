<#
.SYNOPSIS
  Launch Claude Code against Z.ai's GLM Coding Plan (Anthropic-compatible endpoint).

.USAGE
  glm                      start Claude Code on GLM, in the current directory
  glm -SetToken            store/replace the Z.ai Coding Plan key (prompted, hidden input)
  glm -Status              show version, endpoint, token presence, models; no launch, no network
  glm -Model glm-5.3       pin one GLM model for all tiers (default: glm-5.3 big, glm-5.3-flash small)
  glm -Window 200K         context window Claude Code works to (default 1M; accepts 200000, 200K, 1M)
  glm -Clean               use the slim ~/.claude-local profile (no MCP/plugins, far fewer tokens/turn)
  glm -Update              check GitHub now and install a newer glm if there is one, then exit
  glm -NoUpdate            skip the (hourly) update check for this launch
  glm -Version             print the version and exit
  glm <claude args...>     anything else is passed straight to claude (e.g. glm -p "hi", glm --resume)

.NOTES
  Token is stored DPAPI-encrypted (tied to this Windows user) at ~/.config/glm/token.
  Endpoint per https://docs.z.ai/scenario-example/develop-tools/claude . Tiers map to GLM-5.3
  (opus/sonnet/fable) and GLM-5.3-Flash (haiku/subagents). Both are 1M context / 128K output on
  Z.ai's side, and Claude Code is told a 1M window by default; -Window shrinks it.

  /model picker: Claude Code's picker is curated via a "modelPicker" settings block, passed with
  --settings so your own settings.json is never touched. It shows the GLM ids with their context
  and output sizes instead of the Opus/Sonnet/Haiku labels. If you pass your own --settings, the
  curated picker is skipped so the two don't fight.

  Updates: once an hour (or on -Update) the launcher reads the version line of glm.ps1 on
  GitHub (cadfan/glm, main). If it is newer, both files are downloaded, the new script is parsed
  to make sure it is valid, the old one is kept as glm.ps1.bak, and the launch continues on the
  new version. Set GLM_NO_UPDATE=1 to disable the check entirely (e.g. in scripts).
#>

$GlmVersion = "0.1.1"
$RepoRaw    = "https://raw.githubusercontent.com/cadfan/glm/main"

# Hand-parsed so claude's own flags (-p, --output-format, --resume ...) pass through untouched.
$SetToken = $false; $Status = $false; $Clean = $false; $Update = $false; $NoUpdate = $false
$ShowVersion = $false; $Model = ""; $WindowArg = ""; $Rest = @()
for ($i = 0; $i -lt $args.Count; $i++) {
  switch -Regex ($args[$i]) {
    '^-SetToken$' { $SetToken = $true; continue }
    '^-Status$'   { $Status = $true; continue }
    '^-Clean$'    { $Clean = $true; continue }
    '^-Update$'   { $Update = $true; continue }
    '^-NoUpdate$' { $NoUpdate = $true; continue }
    '^-Version$'  { $ShowVersion = $true; continue }
    '^-Model$'    { $i++; $Model = "$($args[$i])"; continue }
    '^-Window$'   { $i++; $WindowArg = "$($args[$i])"; continue }
    default       { $Rest += $args[$i] }
  }
}

# Context window Claude Code works to. Z.ai serves 1M for both GLM ids, so 1M is the default.
function ConvertTo-Tokens([string]$s) {
  if ($s -match '^(\d+(?:\.\d+)?)\s*([kKmM])?$') {
    $n = [double]$Matches[1]
    switch ($Matches[2]) { { $_ -in 'k','K' } { $n *= 1000 }; { $_ -in 'm','M' } { $n *= 1000000 } }
    return [int64]$n
  }
  Write-Host "-Window expects a token count like 200000, 200K or 1M (got '$s')" -ForegroundColor Red; exit 1
}
$WindowTokens = if ($WindowArg) { ConvertTo-Tokens $WindowArg } else { 1000000 }
$window = if ($WindowTokens -ge 1000000) { "{0:n1}M" -f ($WindowTokens / 1e6) -replace '\.0M$', 'M' } else { "{0}K" -f [int]($WindowTokens / 1000) }

if ($ShowVersion) { Write-Output "glm $GlmVersion"; exit 0 }

$BaseUrl      = "https://api.z.ai/api/anthropic"
$TokenDir     = Join-Path $HOME ".config\glm"
$TokenFile    = Join-Path $TokenDir "token"
$SettingsFile = Join-Path $TokenDir "settings.json"
$StampFile    = Join-Path $TokenDir "update-check"
$big   = if ($Model) { $Model } else { "glm-5.3" }        # 1M context, 128K output (Z.ai docs)
$small = if ($Model) { $Model } else { "glm-5.3-flash" }  # also 1M / 128K per Z.ai docs

# ---------------------------------------------------------------- token
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

# ---------------------------------------------------------------- self-update
# Returns a [version], or $null. Sets $script:RemoteReason to say why when it returns $null.
function Get-GlmRemoteVersion {
  $script:RemoteReason = "offline, or GitHub unreachable"
  try {
    $r = Invoke-WebRequest -Uri "$RepoRaw/glm.ps1" -TimeoutSec 5 -UseBasicParsing
    if ($r.Content -match '\$GlmVersion\s*=\s*"(\d+(?:\.\d+)+)"') { return [version]$Matches[1] }
    $script:RemoteReason = "GitHub copy has no version line"
  } catch {}
  return $null
}

# Returns $true if a newer version was installed over this script.
function Update-Glm([bool]$Force) {
  if ($env:GLM_NO_UPDATE) { return $false }
  if (-not $Force -and (Test-Path $StampFile)) {
    if (((Get-Date) - (Get-Item $StampFile).LastWriteTime).TotalHours -lt 1) { return $false }
  }
  New-Item -ItemType Directory -Force $TokenDir | Out-Null
  Set-Content -Path $StampFile -Value (Get-Date -Format o)     # stamp even on failure: no retry storm offline

  $remote = Get-GlmRemoteVersion
  if (-not $remote) {
    if ($Force) { Write-Host "update check failed ($script:RemoteReason)" -ForegroundColor Yellow }
    return $false
  }
  if ($remote -le [version]$GlmVersion) {
    if ($Force) { Write-Host "glm $GlmVersion is current" -ForegroundColor Green }
    return $false
  }

  $dir = $PSScriptRoot
  $tmp = Join-Path $TokenDir "glm.ps1.new"
  try {
    Invoke-WebRequest -Uri "$RepoRaw/glm.ps1" -OutFile $tmp -TimeoutSec 15 -UseBasicParsing
  } catch {
    Write-Host "glm $remote is available but the download failed; keeping $GlmVersion" -ForegroundColor Yellow
    return $false
  }
  $errs = $null
  [System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$errs) | Out-Null
  if ($errs -and $errs.Count) {
    Write-Host "downloaded glm.ps1 ($remote) does not parse; keeping $GlmVersion" -ForegroundColor Red
    Remove-Item $tmp -Force; return $false
  }
  Copy-Item (Join-Path $dir "glm.ps1") (Join-Path $dir "glm.ps1.bak") -Force
  Move-Item $tmp (Join-Path $dir "glm.ps1") -Force
  try { Invoke-WebRequest -Uri "$RepoRaw/glm.cmd" -OutFile (Join-Path $dir "glm.cmd") -TimeoutSec 15 -UseBasicParsing } catch {}
  Write-Host "glm updated $GlmVersion -> $remote (previous kept as $dir\glm.ps1.bak)" -ForegroundColor Green
  return $true
}

# ---------------------------------------------------------------- /model picker
# Claude Code only knows Claude ids, so without this the picker shows Opus/Sonnet/Haiku labels
# over GLM ids. modelPicker (honoured from --settings) replaces the built-in rows with ours.
function Write-GlmPickerSettings([string]$window) {
  $rows = @(
    @{ model = "glm-5.3";       label = "GLM-5.3";       description = "1M context, 128K output. Z.ai Coding Plan. Session window $window" },
    @{ model = "glm-5.3-flash"; label = "GLM-5.3-Flash"; description = "1M context, 128K output, fast. Haiku tier and subagents. Session window $window" }
  )
  foreach ($m in @($big, $small) | Select-Object -Unique) {
    if ($rows.model -notcontains $m) { $rows += @{ model = $m; label = $m; description = "pinned with -Model" } }
  }
  $settings = @{ modelPicker = @{ replaceBuiltInOptions = $true; options = $rows } }
  New-Item -ItemType Directory -Force $TokenDir | Out-Null
  $settings | ConvertTo-Json -Depth 6 | Set-Content -Path $SettingsFile -Encoding UTF8
}

# ---------------------------------------------------------------- dispatch
if ($SetToken) { Save-GlmToken; exit 0 }

if ($Update) {
  if (Update-Glm $true) { exit 0 }   # message already printed; next launch runs the new version
  exit 0
}

$token = Get-GlmToken

if ($Status) {
  $last = if (Test-Path $StampFile) { (Get-Item $StampFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm") } else { "never" }
  Write-Host "version  : $GlmVersion (last update check: $last; install dir: $PSScriptRoot)"
  Write-Host "endpoint : $BaseUrl"
  Write-Host "token    : $(if ($token) { 'stored (' + $token.Substring(0,[Math]::Min(6,$token.Length)) + '...)' } else { 'MISSING - run: glm -SetToken' })"
  Write-Host "model    : $big (opus/sonnet/fable), $small (haiku/subagents)"
  Write-Host "window   : $window ($WindowTokens tokens)"
  Write-Host "picker   : curated via --settings $SettingsFile"
  Write-Host "profile  : $(if ($Clean) { '~/.claude-local (clean)' } else { '~/.claude (full)' })"
  exit 0
}

if (-not $token) {
  Write-Host "No Z.ai token stored. Run:  glm -SetToken" -ForegroundColor Red
  exit 1
}

# Daily update check. If it installed a newer script, re-run that one with the same arguments.
if (-not $NoUpdate -and (Update-Glm $false)) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -NoUpdate @args
  exit $LASTEXITCODE
}

$env:ANTHROPIC_BASE_URL   = $BaseUrl
$env:ANTHROPIC_AUTH_TOKEN = $token
$env:API_TIMEOUT_MS       = "3000000"      # Z.ai recommendation; GLM can be slow on long turns

# Tier mapping: each Claude tier resolves to the GLM id below. -Model <id> pins every tier to one model.
$env:ANTHROPIC_MODEL                = $big
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $big
$env:ANTHROPIC_DEFAULT_FABLE_MODEL  = $big
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $big
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $small
$env:CLAUDE_CODE_SUBAGENT_MODEL     = $small

# Tier display names, honoured when ANTHROPIC_BASE_URL is a gateway. Belt and braces under the
# modelPicker rows: anywhere a tier label still leaks through, it reads as GLM.
$env:ANTHROPIC_DEFAULT_OPUS_MODEL_NAME   = "GLM-5.3"
$env:ANTHROPIC_DEFAULT_FABLE_MODEL_NAME  = "GLM-5.3"
$env:ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = "GLM-5.3"
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME  = "GLM-5.3-Flash"

# Claude Code doesn't know GLM ids, so tell it the window instead of letting it guess (it would
# assume 200K). Auto-compact is tied to the same figure so it does not fire early.
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS  = "$WindowTokens"
$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "$WindowTokens"

if ($Clean) { $env:CLAUDE_CONFIG_DIR = Join-Path $HOME ".claude-local" }

if ($Rest -contains "--settings") {
  Write-Host "note: you passed --settings, so the curated GLM /model picker is skipped" -ForegroundColor Yellow
} else {
  Write-GlmPickerSettings $window
  $Rest = @("--settings", $SettingsFile) + $Rest
}

Write-Host "GLM via Z.ai  v$GlmVersion  model=$big/$small  profile=$(if ($Clean) { 'clean' } else { 'full' })" -ForegroundColor Cyan
claude @Rest
