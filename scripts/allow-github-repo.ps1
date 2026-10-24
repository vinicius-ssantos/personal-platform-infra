[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")]
    [string]$Repository,

    [string]$EnvFile = ".env"
)

$path = [System.IO.Path]::GetFullPath($EnvFile)
if (-not [System.IO.File]::Exists($path)) {
    throw "Environment file not found: $EnvFile"
}

function Find-EnvironmentLine {
    param(
        [byte[]]$Bytes,
        [string]$Name
    )

    $prefix = [System.Text.Encoding]::ASCII.GetBytes("$Name=")
    for ($start = 0; $start -lt $Bytes.Length;) {
        $end = $start
        while ($end -lt $Bytes.Length -and $Bytes[$end] -notin 10, 13) {
            $end++
        }

        $lineLength = $end - $start
        if ($lineLength -ge $prefix.Length) {
            $matches = $true
            for ($index = 0; $index -lt $prefix.Length; $index++) {
                if ($Bytes[$start + $index] -ne $prefix[$index]) {
                    $matches = $false
                    break
                }
            }
            if ($matches) {
                return [pscustomobject]@{
                    Start = $start
                    End = $end
                    Value = [System.Text.Encoding]::ASCII.GetString(
                        $Bytes, $start + $prefix.Length, $lineLength - $prefix.Length
                    )
                }
            }
        }

        $start = $end
        while ($start -lt $Bytes.Length -and $Bytes[$start] -in 10, 13) {
            $start++
        }
    }
}

$bytes = [System.IO.File]::ReadAllBytes($path)
$allowlist = Find-EnvironmentLine -Bytes $bytes -Name "GITHUB_ALLOWED_REPOS"
if ($null -eq $allowlist) {
    throw "GITHUB_ALLOWED_REPOS is not defined in $EnvFile"
}

$requireAllowed = Find-EnvironmentLine -Bytes $bytes -Name "GITHUB_REQUIRE_ALLOWED_REPOS"
if ($allowlist.Value.Length -eq 0 -and $requireAllowed.Value -eq "false") {
    Write-Output "GitHub repository access is unrestricted; no change needed."
    exit 0
}

$repositories = @(
    $allowlist.Value.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_.Trim() }
)

if ($repositories -contains $Repository) {
    Write-Output "Repository is already allowed."
    exit 0
}

$replacement = "GITHUB_ALLOWED_REPOS=" + (($repositories + $Repository) -join ",")
$replacementBytes = [System.Text.Encoding]::ASCII.GetBytes($replacement)
$updated = [byte[]]::new($bytes.Length - ($allowlist.End - $allowlist.Start) + $replacementBytes.Length)
[System.Array]::Copy($bytes, 0, $updated, 0, $allowlist.Start)
[System.Array]::Copy($replacementBytes, 0, $updated, $allowlist.Start, $replacementBytes.Length)
[System.Array]::Copy(
    $bytes,
    $allowlist.End,
    $updated,
    $allowlist.Start + $replacementBytes.Length,
    $bytes.Length - $allowlist.End
)
$temporaryPath = "$path.tmp"

try {
    [System.IO.File]::WriteAllBytes($temporaryPath, $updated)
    [System.IO.File]::Replace($temporaryPath, $path, $null)
} finally {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
}

Write-Output "Repository added to the GitHub allowlist."
