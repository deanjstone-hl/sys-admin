# Bootstrap Windows dev environment from sys-admin stack/
# Usage: .\stack\install-windows.ps1 [-DryRun]
param([switch]$DryRun)

$RepoDir = $PSScriptRoot
$ErrorActionPreference = "Stop"

function Run-Cmd {
  param([string]$Label, [scriptblock]$Block)
  if ($DryRun) { Write-Host "[dry-run] $Label" }
  else { & $Block }
}

# Downloads and installs a GitHub release asset (exe or msi).
function Install-FromGitHub {
  param(
    [string]$Name,
    [string]$Repo,
    [string]$AssetPattern,
    [string]$DetectPath,
    [string[]]$InstallArgs = @("/S")
  )
  Write-Host ""
  Write-Host "==> $Name"
  if (Test-Path $DetectPath) {
    Write-Host "    already installed at $DetectPath"
    return
  }
  if ($DryRun) {
    Write-Host "    [dry-run] Download from github.com/$Repo/releases/latest"
    return
  }
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
  $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
  if (-not $asset) { throw "No asset matching '$AssetPattern' in $($release.tag_name)" }
  $path = "$env:TEMP\$($asset.name)"
  Write-Host "    Downloading $($asset.name) ($($release.tag_name))..."
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $path -UseBasicParsing
  Write-Host "    Running installer..."
  if ($path -match "\.msi$") {
    Start-Process msiexec.exe -ArgumentList (@("/i", $path) + $InstallArgs) -Wait
  } else {
    Start-Process -FilePath $path -ArgumentList $InstallArgs -Wait
  }
  Remove-Item $path -Force
  Write-Host "    $Name installed"
}

Write-Host "==> sys-admin stack: Windows bootstrap (DryRun=$DryRun)"
Write-Host "    Repo: $RepoDir"
Write-Host ""

# --- packages ---

Write-Host "==> Installing packages"

Install-FromGitHub `
  -Name         "PowerShell 7" `
  -Repo         "PowerShell/PowerShell" `
  -AssetPattern "(?i)PowerShell-[\d.]+-win-x64\.msi$" `
  -DetectPath   "$env:ProgramFiles\PowerShell\7\pwsh.exe" `
  -InstallArgs  @("/quiet", "/norestart")

Install-FromGitHub `
  -Name         "Obsidian" `
  -Repo         "obsidianmd/obsidian-releases" `
  -AssetPattern "(?i)^Obsidian-[\d.]+\.exe$" `
  -DetectPath   "$env:LOCALAPPDATA\Obsidian\Obsidian.exe"

Install-FromGitHub `
  -Name         "SyncTrayzor" `
  -Repo         "canton7/SyncTrayzor" `
  -AssetPattern "(?i)SyncTrayzorSetup-x64\.exe$" `
  -DetectPath   "$env:ProgramFiles\SyncTrayzor\SyncTrayzor.exe"

Install-FromGitHub `
  -Name         "Wave Terminal" `
  -Repo         "waveterminal/waveterm" `
  -AssetPattern "(?i)^Wave-Setup-.*\.exe$" `
  -DetectPath   "$env:LOCALAPPDATA\Programs\waveterm\Wave.exe"

Install-FromGitHub `
  -Name         "Git for Windows" `
  -Repo         "git-for-windows/git" `
  -AssetPattern "(?i)^Git-[\d.]+-64-bit\.exe$" `
  -DetectPath   "$env:ProgramFiles\Git\bin\git.exe" `
  -InstallArgs  @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh")

Install-FromGitHub `
  -Name         "GitHub CLI" `
  -Repo         "cli/cli" `
  -AssetPattern "(?i)^gh_[\d.]+_windows_amd64\.msi$" `
  -DetectPath   "$env:ProgramFiles\GitHub CLI\gh.exe" `
  -InstallArgs  @("/quiet", "/norestart")

# Tailscale — installer served from pkgs.tailscale.com, not GitHub releases.
Write-Host ""
Write-Host "==> Tailscale"
$TailscaleExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $TailscaleExe) {
  Write-Host "    already installed at $TailscaleExe"
} else {
  Run-Cmd "Download Tailscale from pkgs.tailscale.com" {
    $url  = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
    $path = "$env:TEMP\tailscale-setup.exe"
    Write-Host "    Downloading..."
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    Start-Process -FilePath $path -ArgumentList @("/quiet", "/norestart") -Wait
    Remove-Item $path -Force
    Write-Host "    Tailscale installed"
  }
}

Install-FromGitHub `
  -Name         "PowerToys" `
  -Repo         "microsoft/PowerToys" `
  -AssetPattern "(?i)^PowerToysSetup-[\d.]+-x64\.exe$" `
  -DetectPath   "$env:ProgramFiles\PowerToys\PowerToys.exe" `
  -InstallArgs  @("/quiet", "/norestart")

# Bitwarden Desktop — bitwarden/clients repo has mixed releases; filter by desktop-v tag.
Write-Host ""
Write-Host "==> Bitwarden Desktop"
$BitwardenExe = "$env:ProgramFiles\Bitwarden\Bitwarden.exe"
# The NSIS installer was "-x64.exe" until 2025; desktop-v2026.10.4 ships it with no arch suffix.
$BitwardenInstallerPattern = "(?i)^Bitwarden-Installer-[\d.]+(-x64)?\.exe$"
if (Test-Path $BitwardenExe) {
  Write-Host "    already installed at $BitwardenExe"
} else {
  Run-Cmd "Download Bitwarden Desktop from GitHub releases" {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/bitwarden/clients/releases?per_page=50"
    $release  = $releases | Where-Object { $_.tag_name -match "^desktop-v" } | Select-Object -First 1
    if (-not $release) { throw "No Bitwarden desktop release found" }
    $asset = $release.assets | Where-Object { $_.name -match $BitwardenInstallerPattern } | Select-Object -First 1
    if (-not $asset) { throw "No Bitwarden installer found in $($release.tag_name)" }
    $path = "$env:TEMP\$($asset.name)"
    Write-Host "    Downloading $($asset.name) ($($release.tag_name))..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $path -UseBasicParsing
    Start-Process -FilePath $path -ArgumentList @("/S") -Wait
    Remove-Item $path -Force
    Write-Host "    Bitwarden Desktop installed"
  }
}

# WezTerm — logic lives in install-wezterm.ps1.
Write-Host ""
Write-Host "==> WezTerm"
$WezTermExe = "$env:ProgramFiles\WezTerm\wezterm.exe"
if (Test-Path $WezTermExe) {
  Write-Host "    already installed at $WezTermExe"
} else {
  Run-Cmd "Run install-wezterm.ps1" {
    & "$PSScriptRoot\install-wezterm.ps1"
  }
}

# --- Speedtest CLI ---
# Ookla doesn't publish on GitHub — direct CDN download.
# Check https://www.speedtest.net/apps/cli if the URL needs updating.

Write-Host ""
Write-Host "==> Speedtest CLI"
$SpeedtestExe = "$env:ProgramFiles\Ookla\Speedtest CLI\speedtest.exe"
if (Test-Path $SpeedtestExe) {
  Write-Host "    already installed at $SpeedtestExe"
} else {
  Run-Cmd "Download Speedtest CLI from Ookla CDN" {
    $zipUrl  = "https://install.speedtest.net/app/cli/ookla-speedtest-win64.zip"
    $zipPath = "$env:TEMP\speedtest-win64.zip"
    $extractDir = "$env:TEMP\speedtest-cli"
    Write-Host "    Downloading..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $installDir = "$env:ProgramFiles\Ookla\Speedtest CLI"
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item "$extractDir\speedtest.exe" $installDir -Force
    Remove-Item $zipPath, $extractDir -Recurse -Force
    Write-Host "    Speedtest CLI installed to $installDir"
    Write-Host "    Add to PATH: $installDir"
  }
}

# --- git config, PowerShell profile, claude shims ---
# Owned by argus-config (sys-admin#153, decided on sys-admin#123): envs/windows/
# {gitconfig,powershell-profile.ps1,bin/}. Its installer keeps them in step with
# the repo on every run, which this one never did for the profile.

Write-Host ""
Write-Host "==> gitconfig, PowerShell profile, claude shims: installed by argus-config"
Write-Host "    Run: pwsh -File \\wsl.localhost\Ubuntu\home\deanj\repos\argus-config\scripts\install-windows.ps1"
Write-Host "    Then set git user once, outside its managed block:"
Write-Host "      git config --global user.name 'Your Name'"
Write-Host "      git config --global user.email 'you@example.com'"
Write-Host "      git config --global user.signingkey 'C:/Users/deanj/.ssh/id_ed25519.pub'"

# --- Goose desktop app ---

Write-Host ""
Write-Host "==> Installing Goose desktop app"
$GooseInstallDir = "$env:LOCALAPPDATA\Programs\Goose"
# The real exe lives inside dist-windows\ alongside its Chromium/Electron resources
$GooseExe = "$GooseInstallDir\dist-windows\Goose.exe"
if (Test-Path $GooseExe) {
  Write-Host "    Goose already installed at $GooseExe"
} else {
  Run-Cmd "Download and extract Goose from GitHub releases" {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/block/goose/releases/latest"
    # Windows desktop app ships as Goose-win32-x64.zip (no exe/msi installer)
    $asset = $release.assets | Where-Object { $_.name -match "(?i)Goose-win32-x64\.zip$" } | Select-Object -First 1
    if (-not $asset) { throw "No Windows zip found in release $($release.tag_name)" }
    $zipPath = "$env:TEMP\goose-win32-x64.zip"
    Write-Host "    Downloading $($asset.name) ($($release.tag_name))..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Write-Host "    Extracting to $GooseInstallDir..."
    New-Item -ItemType Directory -Force -Path $GooseInstallDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $GooseInstallDir -Force
    Remove-Item $zipPath -Force
    Write-Host "    Goose installed at $GooseExe"
  }
}

# --- Goose Argus launcher ---
# Creates a Desktop .cmd launcher that opens Goose with WSL2 ~/argus/ as working directory.
# Uses cmd.exe start /D which reliably sets the process working dir for GUI apps.

Write-Host ""
Write-Host "==> Creating Goose-Argus desktop launcher"
$ArgusWslPath = "\\wsl.localhost\Ubuntu\home\deanj\argus"
$Desktop = [System.Environment]::GetFolderPath("Desktop")
$LauncherPath = "$Desktop\Goose - Argus.cmd"

Run-Cmd "Create Goose-Argus launcher on Desktop" {
  $content = "@echo off`r`nstart `"`" /D `"$ArgusWslPath`" `"%LOCALAPPDATA%\Programs\Goose\dist-windows\Goose.exe`"`r`n"
  Set-Content -Path $LauncherPath -Value $content -NoNewline
  Write-Host "    Launcher created: $LauncherPath"
  Write-Host "    Working dir: $ArgusWslPath"
}

# --- Zed install ---

Write-Host ""
Write-Host "==> Installing Zed"
$ZedExe = "$env:LOCALAPPDATA\Programs\Zed\Zed.exe"
if (Test-Path $ZedExe) {
  Write-Host "    Zed already installed at $ZedExe"
} else {
  Run-Cmd "Download Zed installer from GitHub releases" {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/zed-industries/zed/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match "(?i)^Zed.*x86_64.*\.exe$" } | Select-Object -First 1
    if (-not $asset) { throw "No Windows .exe found in release $($release.tag_name)" }
    $installerPath = "$env:TEMP\$($asset.name)"
    Write-Host "    Downloading $($asset.name) ($($release.tag_name))..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath -UseBasicParsing
    Write-Host "    Running installer (silent)..."
    Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
    Remove-Item $installerPath -Force
    Write-Host "    Zed installed"
  }
}

# --- Zed config ---

Write-Host ""
Write-Host "==> Copying Zed settings"
$ZedSettingsSrc = "$RepoDir\config\windows\zed-settings.json"
$ZedSettingsDst = "$env:APPDATA\Zed\settings.json"
Run-Cmd "Copy $ZedSettingsSrc -> $ZedSettingsDst" {
  New-Item -ItemType Directory -Force -Path (Split-Path $ZedSettingsDst) | Out-Null
  if (Test-Path $ZedSettingsDst) {
    Copy-Item $ZedSettingsDst "$ZedSettingsDst.bak" -Force
    Write-Host "    Backed up existing Zed settings"
  }
  Copy-Item $ZedSettingsSrc $ZedSettingsDst -Force
  Write-Host "    Copied zed-settings.json to $ZedSettingsDst"
}

# --- Zed themes ---

Write-Host ""
Write-Host "==> Copying Zed themes"
$ZedThemesDir = "$env:APPDATA\Zed\themes"
Run-Cmd "Create $ZedThemesDir" {
  New-Item -ItemType Directory -Force -Path $ZedThemesDir | Out-Null
}
foreach ($theme in @("zed-theme-dimidium.json", "zed-theme-dimidium-light.json")) {
  $src = "$RepoDir\config\windows\$theme"
  $dst = "$ZedThemesDir\$($theme -replace '^zed-theme-', '')"
  Run-Cmd "Copy $src -> $dst" {
    Copy-Item $src $dst -Force
    Write-Host "    Copied $theme"
  }
}

# --- Windows Terminal color schemes ---
# Merges Dimidium dark + light into WT settings and wires them as the default
# color schemes. WT must be closed for writes to stick — running WT reverts
# external edits immediately.

Write-Host ""
Write-Host "==> Adding Dimidium color schemes to Windows Terminal"
$WtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$WtSchemeDark  = "$RepoDir\config\windows\wt-scheme-dimidium.json"
$WtSchemeLight = "$RepoDir\config\windows\wt-scheme-dimidium-light.json"
if (Test-Path $WtSettingsPath) {
  Run-Cmd "Merge Dimidium dark + light schemes into WT settings" {
    $wtSettings = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
    $dark  = Get-Content $WtSchemeDark  -Raw | ConvertFrom-Json
    $light = Get-Content $WtSchemeLight -Raw | ConvertFrom-Json
    $keep  = $wtSettings.schemes | Where-Object { $_.name -notin @("Dimidium", "Dimidium Light") }
    $wtSettings.schemes = @($keep) + @($dark, $light)
    # Wire as default dark/light scheme
    $wtSettings.profiles.defaults.colorScheme = [pscustomobject]@{ dark = "Dimidium"; light = "Dimidium Light" }
    $wtSettings | ConvertTo-Json -Depth 10 | Set-Content $WtSettingsPath -Encoding UTF8
    Write-Host "    Dimidium dark + light schemes added and set as defaults"
  }
} else {
  Write-Host "    Windows Terminal settings not found — skipping"
}

# --- Personal apps ---

Install-FromGitHub `
  -Name         "Telegram Desktop" `
  -Repo         "telegramdesktop/tdesktop" `
  -AssetPattern "(?i)^tsetup-x64\.[\d.]+\.exe$" `
  -DetectPath   "$env:APPDATA\Telegram Desktop\Telegram.exe" `
  -InstallArgs  @("/S")

Install-FromGitHub `
  -Name         "Brave Browser" `
  -Repo         "brave/brave-browser" `
  -AssetPattern "^BraveBrowserStandaloneSetup\.exe$" `
  -DetectPath   "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe" `
  -InstallArgs  @("/silent", "/install")

# Zoom — no GitHub releases; stable CDN URL from zoom.us.
Write-Host ""
Write-Host "==> Zoom"
$ZoomExe = "$env:LOCALAPPDATA\Zoom\bin\Zoom.exe"
if (Test-Path $ZoomExe) {
  Write-Host "    already installed at $ZoomExe"
} else {
  Run-Cmd "Download Zoom from zoom.us" {
    $url  = "https://zoom.us/client/latest/ZoomInstallerFull.exe"
    $path = "$env:TEMP\ZoomInstallerFull.exe"
    Write-Host "    Downloading..."
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    Start-Process -FilePath $path -ArgumentList @("/silent") -Wait
    Remove-Item $path -Force
    Write-Host "    Zoom installed"
  }
}

# Spotify — no GitHub releases; stable CDN URL from Spotify.
Write-Host ""
Write-Host "==> Spotify"
$SpotifyExe = "$env:APPDATA\Spotify\Spotify.exe"
if (Test-Path $SpotifyExe) {
  Write-Host "    already installed at $SpotifyExe"
} else {
  Run-Cmd "Download Spotify from download.scdn.co" {
    $url  = "https://download.scdn.co/SpotifySetup.exe"
    $path = "$env:TEMP\SpotifySetup.exe"
    Write-Host "    Downloading..."
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    Start-Process -FilePath $path -Wait
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    Write-Host "    Spotify installed"
  }
}

# Claude Desktop — no stable programmatic download URL; must be installed manually.
Write-Host ""
Write-Host "==> Claude Desktop"
$ClaudeExe = "$env:LOCALAPPDATA\Claude\Claude.exe"
if (Test-Path $ClaudeExe) {
  Write-Host "    already installed at $ClaudeExe"
} else {
  Write-Host "    MANUAL STEP: Download and install from https://claude.ai/download"
}

# --- Power settings ---
# On AC power: lid close does nothing.
# On battery:  lid close hibernates.

Write-Host ""
Write-Host "==> Checking Playwright"
if (Get-Command playwright -ErrorAction SilentlyContinue) {
  Write-Host "    playwright: ok ($(playwright --version))"
} else {
  Write-Host "    Installing Playwright 1.61.1..."
  Run-Cmd "npm install -g playwright@1.61.1" { npm install -g playwright@1.61.1 }
  if (Get-Command playwright -ErrorAction SilentlyContinue) {
    Write-Host "    playwright: $(playwright --version)"
  } else {
    Write-Host "    playwright: not yet on PATH (installed once this isn't a dry run)"
  }
}
if (-not (Test-Path "$env:LOCALAPPDATA\ms-playwright\chromium-1228")) {
  Write-Host "    Installing Chromium browser bundle..."
  Run-Cmd "playwright install chromium" { playwright install chromium }
} else {
  Write-Host "    Chromium cache: $env:LOCALAPPDATA\ms-playwright\chromium-1228"
}

Write-Host ""
Write-Host "==> Configuring lid-close power action"
Run-Cmd "Set lid-close: AC=do nothing, battery=hibernate" {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 2
  powercfg /setactive SCHEME_CURRENT
  Write-Host "    AC lid-close: do nothing"
  Write-Host "    Battery lid-close: hibernate"
}

Write-Host ""
Write-Host "==> Done. Next steps:"
Write-Host "    1. Run argus-config's install-windows.ps1 (gitconfig, profile, claude shims), then set git user (see above)"
Write-Host "    2. Add Speedtest CLI to PATH: $env:ProgramFiles\Ookla\Speedtest CLI"
Write-Host "    3. Authenticate GitHub CLI: gh auth login"
Write-Host "    4. Connect Tailscale: tailscale up"
Write-Host "    5. Restart terminal"
Write-Host "    6. Open Zed and sign in: zed: sign in to zed.dev (Ctrl+Shift+P)"
Write-Host "    7. Launch Goose via 'Goose - Argus' Desktop shortcut"
Write-Host "    8. Log into Bitwarden Desktop and unlock the vault"
Write-Host "    9. Claude Desktop: download manually from https://claude.ai/download if not already installed"
