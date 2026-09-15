<# Registers the local ngrok path-routed environment at user logon. #>

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $root "scripts\ngrok-up.ps1"
$taskName = "MCP Ngrok Environment"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description "Start the local ngrok path proxy and MCP gateway after user logon." -Force | Out-Null

Write-Host "Task '$taskName' installed."
