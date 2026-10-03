# apply.ps1 - the Aditor brain agent (Windows, PowerShell 5.1 compatible).
# Mirrors apply.sh: applies manifest.json steps idempotently, in version order,
# recording the highest applied version in %USERPROFILE%\.aditor-brain\state.json.
# Kill switch: scripts\agent\DISABLED (repo) or %USERPROFILE%\.aditor-brain\DISABLED.
$ErrorActionPreference = 'Stop'

$AgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Vault    = (Resolve-Path (Join-Path $AgentDir '..\..')).Path
$Manifest = Join-Path $AgentDir 'manifest.json'
$StateDir = if ($env:ADITOR_BRAIN_STATE_DIR) { $env:ADITOR_BRAIN_STATE_DIR } else { Join-Path $env:USERPROFILE '.aditor-brain' }
$State    = Join-Path $StateDir 'state.json'
$Log      = Join-Path $StateDir 'agent.log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-Log($m) {
  if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 1048576)) { Move-Item -Force $Log "$Log.1" }
  ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $m) | Add-Content -Path $Log
  Write-Host $m
}

if (Test-Path (Join-Path $AgentDir 'DISABLED')) { Write-Log 'disabled in repo (scripts\agent\DISABLED); skipping'; exit 0 }
if (Test-Path (Join-Path $StateDir 'DISABLED')) { Write-Log 'disabled on this machine; skipping'; exit 0 }

function Get-JsonInt($file, $key) {
  if (-not (Test-Path $file)) { return $null }
  $m = Select-String -Path $file -Pattern ('"{0}"\s*:\s*([0-9]+)' -f $key) | Select-Object -First 1
  if ($m) { return [int]$m.Matches[0].Groups[1].Value }
  return $null
}

function Write-State($applied, $err) {
  $obj = [ordered]@{ applied_version = $applied; last_run = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'); last_error = $err }
  ($obj | ConvertTo-Json) | Set-Content -Path $State
}

# ---- steps (Step-<version>, idempotent, $true on success) ------------------
function Step-1 {
  $dest = Join-Path $Vault '.obsidian\plugins\obsidian-git'
  if ((Test-Path (Join-Path $dest 'main.js')) -and (Test-Path (Join-Path $dest 'manifest.json'))) { return $true }
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Log 'step 1: gh not found; install the sync plugin from Obsidian Community Plugins'; return $false }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $ok = $true
  foreach ($f in @('main.js', 'manifest.json', 'styles.css')) {
    $url = (gh api "repos/Vinzent03/obsidian-git/releases/latest" --jq ".assets[] | select(.name==`"$f`") | .browser_download_url" 2>$null | Select-Object -First 1)
    if ($url) { try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile (Join-Path $dest $f) } catch { if ($f -ne 'styles.css') { $ok = $false } } }
    elseif ($f -ne 'styles.css') { $ok = $false }
  }
  if ($ok -and (Test-Path (Join-Path $dest 'main.js'))) { return $true }
  Write-Log 'step 1: could not install the sync plugin'; return $false
}

$target = Get-JsonInt $Manifest 'version'
if (-not $target) { Write-Log 'could not read manifest version'; exit 1 }
$applied = Get-JsonInt $State 'applied_version'; if (-not $applied) { $applied = 0 }
if ($applied -ge $target) { Write-Log "up to date at version $applied"; exit 0 }

for ($k = $applied + 1; $k -le $target; $k++) {
  $fn = "Step-$k"
  if (Get-Command $fn -ErrorAction SilentlyContinue) {
    Write-Log "applying step $k"
    if (-not (& $fn)) { Write-Log "step $k failed; staying at version $applied"; Write-State $applied "step $k failed"; exit 1 }
  }
}
Write-State $target ''
Write-Log "applied up to version $target"
