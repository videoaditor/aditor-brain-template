# install.ps1 - register the Aditor brain agent as a Windows scheduled task.
# Runs run.ps1 at logon and every 6 hours. Idempotent (-Force refreshes it).
# Called once by bootstrap.ps1; safe to run again.
$ErrorActionPreference = 'Stop'

$AgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Run      = Join-Path $AgentDir 'run.ps1'
$TaskName = 'AditorBrainAgent'

$action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Run`""
$atLogon  = New-ScheduledTaskTrigger -AtLogOn
$every6h  = New-ScheduledTaskTrigger -Once -At (Get-Date) `
             -RepetitionInterval (New-TimeSpan -Hours 6) `
             -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $every6h) -Settings $settings -Force | Out-Null
Write-Host "brain agent installed: scheduled task $TaskName (runs $Run at logon and every 6h)."
