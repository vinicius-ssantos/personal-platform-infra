$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $root "scripts\mcp-wake-proxy.py"
$python = (Get-Command py.exe -ErrorAction Stop).Source
# No console window: see run-hidden.vbs.
$runHidden = Join-Path $PSScriptRoot "run-hidden.vbs"
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B //Nologo `"$runHidden`" `"$python`" -3 `"$scriptPath`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName "MCP Core Wake Proxy" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Wake fixed MCP core services for authenticated public MCP and OAuth traffic." -Force | Out-Null
