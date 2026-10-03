# Aditor Brain - one-shot setup for your own company brain (Windows).
#
# Spins up YOUR brain from the public template: installs the tools, signs you in
# to YOUR GitHub, creates your brain repo from the template, and wires up
# Obsidian + the self-updating agent + Claude Desktop.
#
# Run it directly: powershell -ExecutionPolicy Bypass -File bootstrap.ps1
# Or it ships bundled inside the Install-Aditor-Brain download and is run by the
# double-click launcher (Install-Aditor-Brain.bat).
# Idempotent: safe to re-run; it updates instead of duplicating.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Template   = 'videoaditor/aditor-brain-template'                                                        # the public template to create from
$Name       = if ($env:ADITOR_BRAIN_NAME) { $env:ADITOR_BRAIN_NAME } else { 'company-brain' }           # repo name in YOUR account
$Dest       = if ($env:ADITOR_VAULT_DIR) { $env:ADITOR_VAULT_DIR } else { Join-Path $env:USERPROFILE $Name }
$Visibility = if ($env:ADITOR_BRAIN_VISIBILITY) { $env:ADITOR_BRAIN_VISIBILITY } else { 'private' }     # private (default) or public
$PluginRepo = 'Vinzent03/obsidian-git'
$PlugDir    = Join-Path $Dest '.obsidian\plugins\obsidian-git'

function Say($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

function Refresh-Path {
  $m = [System.Environment]::GetEnvironmentVariable('Path','Machine')
  $u = [System.Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = (@($m, $u) | Where-Object { $_ }) -join ';'
}

function Ensure-Cmd($id, $cmd) {
  if (Get-Command $cmd -ErrorAction SilentlyContinue) { return }
  Write-Host "  installing $id ..."
  winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
  Refresh-Path
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "$cmd is still not available. Close this window, open a new one, and run the installer again (Windows just needs a fresh window to see it)."
  }
}

try {
  Say "Aditor Brain setup"

  # 1. winget (package manager - ships with modern Windows as 'App Installer')
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required. Install 'App Installer' from the Microsoft Store, then run this again."
  }

  # 2. Obsidian + git + gh + node
  Say "Checking tools (Obsidian, git, gh, node)"
  $obsidian = (Test-Path (Join-Path $env:LOCALAPPDATA 'Obsidian\Obsidian.exe')) -or
              (Test-Path (Join-Path ${env:ProgramFiles} 'Obsidian\Obsidian.exe'))
  if (-not $obsidian) {
    Write-Host "  installing Obsidian ..."
    winget install --id Obsidian.Obsidian -e --source winget --accept-package-agreements --accept-source-agreements
  }
  Ensure-Cmd 'Git.Git'           'git'
  Ensure-Cmd 'GitHub.cli'        'gh'
  Ensure-Cmd 'OpenJS.NodeJS.LTS' 'node'

  # 3. GitHub sign-in with YOUR OWN account - only if not already signed in
  gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Say "Sign in to GitHub with your own account"
    gh auth login -h github.com -p https -w
  }
  $Login = (gh api user --jq .login).Trim()

  # 4. Get your brain: clone if it exists, else create it from the template.
  if (Test-Path (Join-Path $Dest '.git')) {
    Say "Brain already here - pulling the latest"
    git -C $Dest pull --rebase --autostash
  } else {
    gh repo view "$Login/$Name" *> $null
    if ($LASTEXITCODE -eq 0) {
      Say "Your brain repo exists ($Login/$Name) - cloning it to $Dest"
      gh repo clone "$Login/$Name" $Dest
    } else {
      Say "Creating your brain from the template -> $Login/$Name"
      gh repo create $Name --template $Template --$Visibility
      # A fresh template copy can take a moment to become cloneable; retry briefly.
      for ($i = 0; $i -lt 5; $i++) {
        gh repo clone "$Login/$Name" $Dest *> $null
        if (Test-Path (Join-Path $Dest '.git')) { break }
        Start-Sleep -Seconds 2
      }
    }
  }
  if (-not (Test-Path (Join-Path $Dest '.git'))) { throw "Could not set up the brain at $Dest" }

  # 5. Install the Obsidian Git plugin (latest release) into the vault
  Say "Installing the sync plugin (Obsidian Git)"
  New-Item -ItemType Directory -Force -Path $PlugDir | Out-Null
  foreach ($f in 'main.js', 'manifest.json', 'styles.css') {
    $url = gh api "repos/$PluginRepo/releases/latest" --jq ".assets[] | select(.name==`"$f`") | .browser_download_url" 2>$null | Select-Object -First 1
    if ($url) {
      try { Invoke-WebRequest $url -OutFile (Join-Path $PlugDir $f) -UseBasicParsing }
      catch { Write-Host "  (could not fetch $f - Obsidian can install the plugin from Community Plugins instead)" }
    }
  }
  # the vault already ships community-plugins.json + the plugin's data.json, so it auto-enables and auto-syncs

  # 6. Point Claude Desktop at the vault (filesystem MCP) - merged into any existing config
  Say "Configuring Claude Desktop file access"
  function To-HT($o) {
    if ($o -is [System.Collections.IDictionary]) { $h=@{}; foreach ($k in $o.Keys) { $h[$k]=To-HT $o[$k] }; return $h }
    if ($o -is [System.Management.Automation.PSCustomObject]) { $h=@{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name]=To-HT $p.Value }; return $h }
    if ($o -is [object[]]) { return ,@($o | ForEach-Object { To-HT $_ }) }
    return $o
  }
  $CfgDir  = Join-Path $env:APPDATA 'Claude'
  New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
  $CfgPath = Join-Path $CfgDir 'claude_desktop_config.json'
  $cfg = @{}
  if (Test-Path $CfgPath) {
    try { $cfg = To-HT (Get-Content $CfgPath -Raw | ConvertFrom-Json) } catch { $cfg = @{} }
  }
  if ($null -eq $cfg -or $cfg -isnot [hashtable]) { $cfg = @{} }
  if (-not $cfg.ContainsKey('mcpServers') -or $cfg['mcpServers'] -isnot [hashtable]) { $cfg['mcpServers'] = @{} }
  $servers = $cfg['mcpServers']
  $fs = $servers['filesystem']
  if ($fs -is [hashtable] -and $fs['args'] -is [System.Collections.IList]) {
    if ($fs['args'] -notcontains $Dest) { $fs['args'] = @($fs['args']) + $Dest }  # keep any folders already allowed
  } else {
    # On Windows, Claude Desktop launches npx reliably via cmd /c
    $servers['filesystem'] = @{ command = 'cmd'; args = @('/c', 'npx', '-y', '@modelcontextprotocol/server-filesystem', $Dest) }
  }
  [System.IO.File]::WriteAllText($CfgPath, ($cfg | ConvertTo-Json -Depth 20))
  Write-Host "  wrote $CfgPath"

  # 6b. Install the brain agent: keeps this setup current after install.
  Say "Installing the brain agent (keeps your setup up to date)"
  try { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'scripts\agent\install.ps1') } catch { Write-Host "  (brain agent install skipped)" }
  try { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'scripts\agent\run.ps1') | Out-Null } catch { }

  # 7. Open Obsidian on the vault
  Say "Opening Obsidian"
  $enc = [uri]::EscapeDataString($Dest)
  try { Start-Process "obsidian://open?path=$enc" } catch { Write-Host "  (open Obsidian and choose 'Open folder as vault' -> $Dest)" }

  Write-Host "`nDone." -ForegroundColor Green
  Write-Host "Your brain:  $Login/$Name  (cloned to $Dest)"
  Write-Host "Obsidian: should open the vault at $Dest (confirm 'Open as vault' if asked)."
  Write-Host "Your edits sync to GitHub automatically every few minutes."
  Write-Host "`nClaude Desktop: fully quit it (right-click the tray icon -> Quit) and reopen,"
  Write-Host "so it picks up the vault. It can then read and write your notes (it asks permission per file)."
  Write-Host "`nPrefer Claude Code? Just point it at $Dest - it reads the law (AGENTS.md) on its own."
}
catch {
  Write-Host "`nSomething went wrong:" -ForegroundColor Red
  Write-Host ("  " + $_.Exception.Message) -ForegroundColor Red
  Write-Host "`nCopy the message above and check the README for help."
}
