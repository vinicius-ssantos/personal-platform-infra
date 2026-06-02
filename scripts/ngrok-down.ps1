$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

Write-Host "Stopping ngrok..."
$ngrokProcesses = Get-Process ngrok -ErrorAction SilentlyContinue
if ($ngrokProcesses) {
    $ngrokProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped $($ngrokProcesses.Count) ngrok process(es)."
}
else {
    Write-Host "No ngrok process found."
}

if (Test-Path "compose/docker-compose.yml") {
    Write-Host "Stopping Compose ngrok-proxy..."
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & docker compose -f compose/docker-compose.yml --env-file .env stop ngrok-proxy 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -eq 0) {
        Write-Host "Stopped Compose ngrok-proxy."
    }
    else {
        Write-Host "Compose ngrok-proxy was not running or could not be stopped."
    }
}

Write-Host "Local app containers were left running. Use 'just compose-down' to stop everything."
