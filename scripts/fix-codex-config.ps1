param(
    [string]$RepoRoot = "C:\Users\vinicius\Documents\workspace\personal-platform-infra"
)

$ErrorActionPreference = "Stop"

$codexDir = Join-Path $RepoRoot ".codex"
$configPath = Join-Path $codexDir "config.toml"

if (-not (Test-Path -LiteralPath $codexDir)) {
    New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
}

$content = @'
model = "gpt-5.5"
model_reasoning_effort = "high"

approval_policy = "on-request"
sandbox_mode = "workspace-write"
network_access = false

[history]
persistence = "none"

[agents]
max_threads = 4
max_depth = 1

[profiles.project-edit]
default_permissions = "project-edit"
project_doc_fallback_filenames = ["AGENTS.md", ".AGENTS.md"]

[profiles.project-edit.permissions]
read = "all"
write = "project"
network = false

[profiles.project-edit.permissions.paths]
".env" = "deny"
".env.*" = "deny"
".mcp.json" = "deny"
"opencode.local.json" = "deny"
".kube" = "deny"
".k3d" = "deny"
".age" = "deny"
"secrets" = "deny"
"node_modules" = "deny"
".opencode/node_modules" = "deny"
".pytest_cache" = "deny"
".sandbox" = "deny"
"dist" = "deny"
".wrangler" = "deny"
".tmp-*" = "deny"
"*.log" = "deny"
'@

Set-Content -LiteralPath $configPath -Value $content -Encoding utf8

Write-Host "Arquivo criado em: $configPath"
Write-Host ""
Get-Content -LiteralPath $configPath
