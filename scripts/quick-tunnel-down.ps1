$ErrorActionPreference = "Stop"

$ports = @(8765, 8001, 8080, 8010, 8020, 8030, 8040)
$processes = Get-CimInstance Win32_Process -Filter "name = 'cloudflared.exe'" -ErrorAction SilentlyContinue
$stopped = 0

foreach ($process in $processes) {
    foreach ($port in $ports) {
        if ($process.CommandLine -like "*tunnel*--url*localhost:$port*") {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped += 1
            break
        }
    }
}

Write-Host "Stopped $stopped Cloudflare quick tunnel process(es)."
