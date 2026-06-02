param(
    [int]$HttpsPort = 443
)

$ErrorActionPreference = "Stop"

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    if ($Name -eq "tailscale") {
        $candidates = @(
            "$env:ProgramFiles\Tailscale\tailscale.exe",
            "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
        )
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path $candidate)) {
                return $candidate
            }
        }
    }

    throw "$Name not found in PATH."
}

$Tailscale = Get-CommandPath "tailscale"

Write-Host "Stopping Tailscale Funnel on HTTPS port $HttpsPort..."
& $Tailscale funnel "--https=$HttpsPort" off
if ($LASTEXITCODE -ne 0) {
    throw "tailscale funnel off failed."
}

Write-Host "Tailscale Funnel stopped. Local app containers were left running."
