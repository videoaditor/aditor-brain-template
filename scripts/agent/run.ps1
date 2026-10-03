# run.ps1 - scheduled entry point for the Aditor brain agent (Windows).
# The AditorBrainAgent scheduled task runs this at logon and every 6 hours.
# It pulls the repo and applies the desired state, refusing an unexpected checkout.
$ErrorActionPreference = 'Stop'

$AgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Vault    = (Resolve-Path (Join-Path $AgentDir '..\..')).Path
$StateDir = if ($env:ADITOR_BRAIN_STATE_DIR) { $env:ADITOR_BRAIN_STATE_DIR } else { Join-Path $env:USERPROFILE '.aditor-brain' }
$Log      = Join-Path $StateDir 'agent.log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
function Note($m) { ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $m) | Add-Content -Path $Log }

Set-Location $Vault

$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
if ($branch -ne 'main') { Note "run: not on main ($branch); skipping"; exit 0 }
git diff --quiet -- scripts/agent 2>$null
if ($LASTEXITCODE -ne 0) { Note 'run: uncommitted changes under scripts/agent; skipping'; exit 0 }
git fsck --no-progress --connectivity-only 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Note 'run: git fsck failed; skipping'; exit 0 }

git pull --ff-only 2>&1 | Add-Content -Path $Log

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AgentDir 'apply.ps1')
