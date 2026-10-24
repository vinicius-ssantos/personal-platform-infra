# Read-only source database backup and isolated restore rehearsal (VagaDeck #86).
# Uses an ephemeral, network-disconnected PostgreSQL container for the restore.
# It DOES NOT restore into, stop, or delete the source Keycloak/PostgreSQL services.
param(
    [switch]$ConfirmIsolatedLocalLab,
    [switch]$KeepBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmIsolatedLocalLab) {
    throw 'Explicit -ConfirmIsolatedLocalLab acknowledgement is required.'
}
if (-not $env:LOCALAPPDATA -or -not $env:USERNAME) {
    throw 'This rehearsal requires a dedicated Windows user profile.'
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is not available.'
}
# Refuse remote Docker contexts: this program must only touch the local Windows daemon.
if ($env:DOCKER_HOST) {
    throw 'An explicit DOCKER_HOST override is not allowed for the local rehearsal.'
}
$contextHost = ((& docker context inspect --format '{{.Endpoints.docker.Host}}') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $contextHost -notmatch '^npipe:////\./pipe/[A-Za-z0-9_.-]+$') {
    throw 'Only a local Windows Docker named-pipe context is allowed.'
}

$privateRoot = Join-Path $env:LOCALAPPDATA 'VagaDeck\keycloak-prod-rehearsal'
$databaseEnv = Join-Path $privateRoot 'postgres.env'
$keycloakEnv = Join-Path $privateRoot 'keycloak.env'
$keystore = Join-Path $privateRoot 'keycloak.p12'
$compose = Join-Path $PSScriptRoot 'compose.yaml'
$expectedProject = 'vagadeck-oidc-private'
$expectedImage = 'postgres:17-alpine@sha256:eee6c6e1b0894fa4fe0075eb054af9fd1cf39a35321c2d4110626cfe506411fb'
$backupDir = Join-Path $privateRoot 'backup-restore-drills'

foreach ($required in @($databaseEnv, $keycloakEnv, $keystore, $compose)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw 'An expected local-only rehearsal file is missing.'
    }
}
# Refuse to point at an externally named Keycloak, even with local Docker access.
$hosts = @(Get-Content -LiteralPath $keycloakEnv | Where-Object { $_ -like 'KC_HOSTNAME=*' })
if ($hosts.Count -ne 1 -or $hosts[0] -ne 'KC_HOSTNAME=https://localhost:19443') {
    throw 'Only the known localhost Keycloak rehearsal may be backed up.'
}

# Override external/ambient Compose variables with fixed user-local rehearsal files.
$env:VAGADECK_OIDC_DB_CONFIG_FILE = $databaseEnv
$env:VAGADECK_OIDC_KEYCLOAK_CONFIG_FILE = $keycloakEnv
$env:VAGADECK_OIDC_KEYSTORE_FILE = $keystore
$env:VAGADECK_OIDC_LOOPBACK_PORT = '19443'
$env:VAGADECK_OIDC_MANAGEMENT_PORT = '19001'

$sourceId = ((& docker compose -f $compose ps -q postgres) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $sourceId -notmatch '^[0-9a-f]{12,64}$') {
    throw 'The expected local PostgreSQL Compose service is not running.'
}
$labels = ((& docker inspect --format '{{json .Config.Labels}}' $sourceId) -join '') | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or
    $labels.'com.docker.compose.project' -ne $expectedProject -or
    $labels.'com.docker.compose.service' -ne 'postgres') {
    throw 'Refusing an unrecognized PostgreSQL container.'
}
$sourceImage = ((& docker inspect --format '{{.Config.Image}}' $sourceId) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $sourceImage -ne $expectedImage) {
    throw 'Refusing a PostgreSQL container using an unexpected image.'
}
$bindings = ((& docker inspect --format '{{json .HostConfig.PortBindings}}' $sourceId) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $bindings -ne '{}') {
    throw 'Source PostgreSQL unexpectedly publishes a host port.'
}
$sourceMounts = @(((& docker inspect --format '{{json .Mounts}}' $sourceId) -join '') | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or
    @($sourceMounts | Where-Object {
        $_.Type -eq 'volume' -and $_.Name -eq 'vagadeck-oidc-private_postgres-data' -and
        $_.Destination -eq '/var/lib/postgresql/data'
    }).Count -ne 1) {
    throw 'Source PostgreSQL is not backed by the isolated rehearsal volume.'
}

function Invoke-DockerChecked([string[]]$Arguments) {
    & docker @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ('Docker operation failed: ' + $Arguments[0])
    }
}

function Get-PostgresCount([string]$Container, [string]$Sql) {
    $lines = @(& docker exec $Container psql -X --quiet --tuples-only --no-align --set ON_ERROR_STOP=1 -U keycloak -d keycloak -c $Sql)
    if ($LASTEXITCODE -ne 0) {
        throw 'A PostgreSQL verification query failed.'
    }
    $candidate = (($lines | Where-Object { $_ -match '\S' }) -join '').Trim()
    if ($candidate -notmatch '^\d+$') {
        throw 'PostgreSQL returned a non-numeric verification result.'
    }
    return [long]::Parse($candidate)
}

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
& icacls $backupDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)(F)" /grant:r 'SYSTEM:(OI)(CI)(F)' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot secure the temporary local backup directory.'
}

$unique = [guid]::NewGuid().ToString('N').Substring(0, 12)
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$localDump = Join-Path $backupDir ("keycloak-$timestamp-$unique.dump")
$sourceDump = "/tmp/vagadeck-rehearsal-$unique.dump"
$targetDump = '/tmp/vagadeck-restore.dump'
$scratch = "vagadeck-oidc-restore-$unique"
$sourceDumpCreated = $false
$scratchStarted = $false
$verified = $false
$priorPgPassword = [Environment]::GetEnvironmentVariable('POSTGRES_PASSWORD', 'Process')

try {
    # The custom-format archive is created IN the source container first.
    # Do not use PowerShell's redirection to pipe binary pg_dump output.
    $sourceDumpCreated = $true
    Invoke-DockerChecked -Arguments @('exec', $sourceId, 'pg_dump', '--format=custom', '--no-owner', '--no-acl',
        '-U', 'keycloak', '-d', 'keycloak', '--file', $sourceDump)
    Invoke-DockerChecked -Arguments @('cp', "${sourceId}:$sourceDump", $localDump)
    if ((Get-Item -LiteralPath $localDump).Length -lt 1024) {
        throw 'The PostgreSQL archive is suspiciously small.'
    }
    & icacls $localDump /inheritance:r /grant:r "${env:USERNAME}:(R,W)" /grant:r 'SYSTEM:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot restrict backup file ACLs.'
    }
    $digest = (Get-FileHash -LiteralPath $localDump -Algorithm SHA256).Hash

    # The scratch container is ephemeral: no network, no ports and no mounted volume.
    # Docker receives the password from the process environment, not CLI history.
    $randomBytes = New-Object byte[] 36
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $env:POSTGRES_PASSWORD = [Convert]::ToBase64String($randomBytes)
    Invoke-DockerChecked -Arguments @('run', '--detach', '--rm', '--network', 'none', '--name', $scratch,
        '--env', 'POSTGRES_PASSWORD', '--env', 'POSTGRES_DB=keycloak', '--env', 'POSTGRES_USER=keycloak',
        $expectedImage)
    $scratchStarted = $true
    $scratchNetwork = ((& docker inspect --format '{{.HostConfig.NetworkMode}}' $scratch) -join '').Trim()
    $scratchPorts = ((& docker inspect --format '{{json .HostConfig.PortBindings}}' $scratch) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $scratchNetwork -ne 'none' -or $scratchPorts -ne '{}') {
        throw 'Scratch PostgreSQL has unexpected network or host-port access.'
    }

    $ready = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        # The postgres entrypoint temporarily starts PostgreSQL during initdb,
        # then stops it before launching the final PID 1 postgres daemon.
        # pg_isready alone can yield a false-positive during this transition.
        $daemon = ((& docker exec $scratch cat /proc/1/comm 2>$null) -join '').Trim()
        if ($LASTEXITCODE -eq 0 -and $daemon -eq 'postgres') {
            $probe = ((& docker exec $scratch psql -X --quiet --tuples-only --no-align -U keycloak -d keycloak -c 'SELECT 1' 2>$null) -join '').Trim()
            if ($LASTEXITCODE -eq 0 -and $probe -eq '1') {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw 'Disposable PostgreSQL did not become ready.'
    }
    Invoke-DockerChecked -Arguments @('cp', $localDump, "${scratch}:$targetDump")
    Invoke-DockerChecked -Arguments @('exec', $scratch, 'pg_restore', '--list', $targetDump)
    Invoke-DockerChecked -Arguments @('exec', $scratch, 'pg_restore', '--exit-on-error', '--single-transaction',
        '--no-owner', '--no-acl', '-U', 'keycloak', '-d', 'keycloak', $targetDump)

    # Compare narrow aggregate evidence only; never print OIDC subjects, account names or data.
    $sourceRealms = Get-PostgresCount $sourceId 'SELECT COUNT(*) FROM realm'
    $scratchRealms = Get-PostgresCount $scratch 'SELECT COUNT(*) FROM realm'
    $sourceTables = Get-PostgresCount $sourceId "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"
    $scratchTables = Get-PostgresCount $scratch "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"
    if ($sourceRealms -lt 1 -or $sourceRealms -ne $scratchRealms -or
        $sourceTables -lt 1 -or $sourceTables -ne $scratchTables) {
        throw 'Disposable restore diverges from the local source database.'
    }

    $verified = $true
    Write-Output 'KEYCLOAK_POSTGRES_DISPOSABLE_RESTORE_PASSED'
    Write-Output ("REALM_COUNT_MATCH=$scratchRealms TABLE_COUNT_MATCH=$scratchTables")
    Write-Output ("ARCHIVE_SHA256=$digest")
    Write-Output 'SOURCE_DB_UNMODIFIED_BY_DRILL; NO_EXTERNAL_PORT; SCRATCH_CONTAINER_REMOVED_IN_FINALLY'
} finally {
    if ($scratchStarted) {
        & docker rm --force $scratch | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Scratch container cleanup requires manual investigation.' }
    }
    if ($sourceDumpCreated) {
        & docker exec $sourceId rm -f -- $sourceDump | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Temporary archive inside source container requires manual cleanup.' }
    }
    if ((Test-Path -LiteralPath $localDump) -and (-not $KeepBackup -or -not $verified)) {
        Remove-Item -LiteralPath $localDump -Force
    }
    [Environment]::SetEnvironmentVariable('POSTGRES_PASSWORD', $priorPgPassword, 'Process')
}
if ($KeepBackup) {
    Write-Warning 'A sensitive unencrypted local backup was retained under user ACLs. Encrypt it or remove it immediately after review.'
}
