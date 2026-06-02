param(
    [string]$ClusterName = "personal-platform"
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $File $($Arguments -join ' ')"
    }
}

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw "$Name not found in PATH"
}

$K3d = Get-CommandPath "k3d"
$Kubectl = Get-CommandPath "kubectl"

$clusterExists = (& $K3d cluster list 2>$null | Select-String -Pattern "^$ClusterName\s") -ne $null
if ($clusterExists) {
    Write-Host "Starting existing k3d cluster '$ClusterName'..."
    Invoke-Checked $K3d @("cluster", "start", $ClusterName)
}
else {
    Write-Host "Creating k3d cluster '$ClusterName'..."
    Invoke-Checked $K3d @("cluster", "create", $ClusterName, "--config", "k8s/overlays/local/k3d-config.yaml")
}

$KubeconfigPath = Join-Path $env:USERPROFILE ".config\k3d\kubeconfig-$ClusterName.yaml"
if (-not (Test-Path $KubeconfigPath)) {
    Invoke-Checked $K3d @("kubeconfig", "write", $ClusterName)
}

$kubeconfigText = [System.IO.File]::ReadAllText($KubeconfigPath)
$normalizedKubeconfigText = $kubeconfigText -replace "https://host\.docker\.internal:", "https://127.0.0.1:"
if ($normalizedKubeconfigText -ne $kubeconfigText) {
    [System.IO.File]::WriteAllText($KubeconfigPath, $normalizedKubeconfigText, [System.Text.UTF8Encoding]::new($false))
}

$env:KUBECONFIG = $KubeconfigPath
Invoke-Checked $Kubectl @("config", "use-context", "k3d-$ClusterName")

Write-Host "Waiting for Kubernetes API..."
$deadline = (Get-Date).AddSeconds(60)
$apiReady = $false
while ((Get-Date) -lt $deadline) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Kubectl cluster-info --request-timeout=5s *> $null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -eq 0) {
        $apiReady = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $apiReady) {
    Invoke-Checked $Kubectl @("cluster-info", "--request-timeout=10s")
}

Write-Host "Applying local Kubernetes overlay..."
Invoke-Checked $Kubectl @("apply", "-k", "k8s/overlays/local")

Write-Host ""
Write-Host "Cluster ready. Run 'just k3d-secrets' to inject real API tokens from .env."
