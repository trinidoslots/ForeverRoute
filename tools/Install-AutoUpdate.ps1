# Registers a scheduled task that runs Update.ps1 at every logon and every 6 hours.
#   .\tools\Install-AutoUpdate.ps1           # install
#   .\tools\Install-AutoUpdate.ps1 -Remove   # uninstall
param([switch]$Remove)
$ErrorActionPreference = "Stop"
$name = "ForeverRoute update"

if ($Remove) {
	Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
	Write-Host "Removed the task '$name'." -ForegroundColor Green
	exit 0
}

$script = Join-Path $PSScriptRoot "Update.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
	-Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Quiet"
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 6)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
	-ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $name -Action $action -Trigger @($logon, $repeat) -Settings $settings `
	-Description "Pulls the newest ForeverRoute from GitHub (skips while WoW runs)." -Force | Out-Null
Write-Host "Task '$name' installed: runs at logon and every 6 hours." -ForegroundColor Green
