param(
    [int]$LocalPort = 18040
)

$ErrorActionPreference = "Stop"

Write-Host "Stopping ngrok..."
Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Stopping central MCP gateway port-forward..."
$processes = Get-CimInstance Win32_Process -Filter "name = 'kubectl.exe'" -ErrorAction SilentlyContinue
foreach ($process in $processes) {
    if ($process.CommandLine -like "*port-forward*" -and
        $process.CommandLine -like "*central-mcp-gateway*" -and
        $process.CommandLine -like "*${LocalPort}:8080*") {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped kubectl port-forward process $($process.ProcessId)"
    }
}

Write-Host "k3d cluster was left running. Use 'just k8s-local-down' if you want to delete it."
