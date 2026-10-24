# Prepare restricted local-only credentials for a disposable Keycloak prod-mode rehearsal.
param([string]$Root = (Join-Path $env:LOCALAPPDATA 'VagaDeck\keycloak-prod-rehearsal'))
$ErrorActionPreference = 'Stop'
$keycloakEnv = Join-Path $Root 'keycloak.env'
$dbEnv = Join-Path $Root 'postgres.env'
$legacy = Join-Path $Root 'runtime.env'
$keystore = Join-Path $Root 'keycloak.p12'
$certificate = Join-Path $Root 'keycloak.crt'
function Protect-PrivateFile([string]$path) {
    icacls $path /inheritance:r /grant:r "${env:USERNAME}:(R,W)" /grant:r 'SYSTEM:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to restrict local file ACL: $path" }
}
function Store-Env([string]$path,[string[]]$lines) {
    [IO.File]::WriteAllLines($path, $lines, [Text.Encoding]::ASCII)
    Protect-PrivateFile $path
}
function New-Secret {
    $bytes = New-Object byte[] 42
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
if ((Test-Path $keycloakEnv) -xor (Test-Path $dbEnv)) {
    throw 'Partial private configuration detected; no secrets regenerated.'
}
if ((Test-Path $keycloakEnv) -and (Test-Path $dbEnv) -and (Test-Path $keystore)) {
    Write-Output 'PRIVATE_REHEARSAL_ALREADY_PREPARED'
} elseif ((Test-Path $legacy) -and (Test-Path $keystore)) {
    # One-time migration from an earlier LOCAL rehearsal config that shared
    # both sets of credentials. No secret is printed and values are preserved.
    $content = @(Get-Content $legacy)
    $db = @($content | Where-Object { $_ -like 'POSTGRES_PASSWORD=*' })
    $kc = @($content | Where-Object { $_ -notlike 'POSTGRES_PASSWORD=*' })
    if ($db.Count -ne 1 -or -not @($kc | Where-Object { $_ -like 'KC_DB_PASSWORD=*' }).Count) {
        throw 'Cannot split legacy credentials safely.'
    }
    Store-Env $dbEnv $db
    Store-Env $keycloakEnv $kc
    Remove-Item -LiteralPath $legacy -Force
    Write-Output 'LOCAL_REHEARSAL_CREDENTIALS_SPLIT'
} else {
    if (Test-Path $keystore) { throw 'Keystore exists without valid private configuration.' }
    $keytool = $null
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\keytool.exe'))) {
        $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    } else {
        $found = Get-Command keytool.exe -ErrorAction SilentlyContinue
        if ($found) { $keytool = $found.Source }
    }
    if (-not $keytool) { throw 'Java keytool not found; set JAVA_HOME to a local JDK.' }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $dbPassword = New-Secret
    $adminPassword = New-Secret
    $storePassword = New-Secret
    & $keytool -genkeypair -alias vagadeck-prod-rehearsal -keyalg RSA -keysize 3072 -validity 30 -storetype PKCS12 -keystore $keystore -storepass $storePassword -keypass $storePassword -dname 'CN=localhost, OU=VagaDeck Rehearsal' -ext 'SAN=DNS:localhost,IP:127.0.0.1' -noprompt
    if ($LASTEXITCODE -ne 0) { throw 'Local keystore creation failed.' }
    & $keytool -exportcert -rfc -alias vagadeck-prod-rehearsal -keystore $keystore -storetype PKCS12 -storepass $storePassword -file $certificate | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Public certificate export failed.' }
    Store-Env $dbEnv @("POSTGRES_PASSWORD=$dbPassword")
    Store-Env $keycloakEnv @(
        'KC_HOSTNAME=https://localhost:19443',
        "KC_DB_PASSWORD=$dbPassword",
        'KC_BOOTSTRAP_ADMIN_USERNAME=vagadeck-rehearsal-admin',
        "KC_BOOTSTRAP_ADMIN_PASSWORD=$adminPassword",
        "KC_HTTPS_KEY_STORE_PASSWORD=$storePassword"
    )
    Protect-PrivateFile $keystore
    Protect-PrivateFile $certificate
    Write-Output 'LOCAL_ONLY_PRODUCTION_MODE_REHEARSAL_PREPARED'
}
Write-Output "VAGADECK_OIDC_DB_CONFIG_FILE=$dbEnv"
Write-Output "VAGADECK_OIDC_KEYCLOAK_CONFIG_FILE=$keycloakEnv"
Write-Output "VAGADECK_OIDC_KEYSTORE_FILE=$keystore"
Write-Output "LOCAL_CA_CERTIFICATE=$certificate"
Write-Output 'NO_SECRET_PRINTED'
