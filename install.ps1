# Installs glm into ~/.local/bin and puts that folder on the user PATH.
# Run from a clone:   .\install.ps1
# Or one-liner:       irm https://raw.githubusercontent.com/cadfan/glm/main/install.ps1 | iex
$ErrorActionPreference = "Stop"
$bin = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force $bin | Out-Null

$src = $PSScriptRoot
if (-not $src -or -not (Test-Path (Join-Path $src "glm.ps1"))) {
  # piped via irm | iex: fetch the files from GitHub
  $raw = "https://raw.githubusercontent.com/cadfan/glm/main"
  foreach ($f in "glm.ps1", "glm.cmd") { Invoke-WebRequest "$raw/$f" -OutFile (Join-Path $bin $f) }
} else {
  Copy-Item (Join-Path $src "glm.ps1"), (Join-Path $src "glm.cmd") $bin -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $bin) {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$bin", "User")
  $env:Path += ";$bin"
  Write-Host "added $bin to your user PATH (open a new terminal for other windows to see it)"
}
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "Claude Code not found. Install it first:  irm https://claude.ai/install.ps1 | iex" -ForegroundColor Yellow
}
Write-Host "installed. Next:  glm -SetToken   then   glm" -ForegroundColor Green
