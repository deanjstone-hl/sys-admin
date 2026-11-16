# Install WezTerm and deploy wezterm.lua config
# Usage (run from elevated PowerShell — bypasses UNC script signing restriction):
#   PowerShell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\deanj\repos\sys-admin\stack\install-wezterm.ps1

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot

# ── Install WezTerm ───────────────────────────────────────────────────────────

Write-Host "==> Fetching latest WezTerm nightly release..."
$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/wez/wezterm/releases?per_page=10"
$release = $releases | Where-Object { $_.tag_name -match "nightly" } | Select-Object -First 1
if (-not $release) { $release = $releases[0] }  # fall back to most recent if no nightly tag
Write-Host "    Latest: $($release.tag_name)"

$asset = $release.assets | Where-Object { $_.name -match "-setup\.exe$" } | Select-Object -First 1
if (-not $asset) {
  Write-Host "    Available assets:"
  $release.assets | ForEach-Object { Write-Host "      $($_.name)" }
  throw "No Windows .setup.exe found in release $($release.tag_name)"
}

$installerPath = "$env:TEMP\$($asset.name)"
Write-Host "==> Downloading $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath -UseBasicParsing
Write-Host "    Saved to $installerPath"

Write-Host "==> Running installer (silent)..."
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
Remove-Item $installerPath -Force
Write-Host "    WezTerm installed"

# ── Deploy wezterm.lua ────────────────────────────────────────────────────────

$WeztermSrc = "$RepoDir\config\windows\wezterm.lua"
$WeztermDst = "$env:USERPROFILE\.wezterm.lua"

Write-Host ""
Write-Host "==> Copying wezterm.lua -> $WeztermDst"
if (Test-Path $WeztermDst) {
  Copy-Item $WeztermDst "$WeztermDst.bak" -Force
  Write-Host "    Backed up existing config to .wezterm.lua.bak"
}
Copy-Item $WeztermSrc $WeztermDst -Force
Write-Host "    Done"

Write-Host ""
Write-Host "==> Complete. Launch WezTerm from the Start menu."
