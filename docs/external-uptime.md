# Uptime externo

Monitoração de disponibilidade feita **de fora** da plataforma. Grafana/Loki
alertam sobre problemas internos, mas se o cluster, o Tunnel ou a VPS inteira
caírem, nada interno consegue avisar. Duas camadas complementares:

## 1. Dead-man's switch dos CronJobs (healthchecks.io)

Os CronJobs `mcp-social-backup` (diário, 03:00 UTC) e
`mcp-social-restore-verify` (semanal, domingo 04:30 UTC) pingam uma URL do
[healthchecks.io](https://healthchecks.io) **ao final de uma execução
bem-sucedida**. Se o ping não chegar dentro da janela esperada, o
healthchecks.io dispara o alerta (e-mail/Telegram/etc.) — mesmo que o cluster
esteja completamente fora do ar.

Setup:

1. Crie dois checks no healthchecks.io:
   - `mcp-social-backup` — período *1 day*, grace *2 hours*.
   - `mcp-social-restore-verify` — período *1 week*, grace *6 hours*.
2. Copie as URLs de ping e adicione ao Secret `platform-secrets` (namespace
   `mcp`) via fluxo SOPS (`just secrets-edit-vps-k8s`):

   ```yaml
   HEALTHCHECKS_BACKUP_URL: https://hc-ping.com/<uuid-backup>
   HEALTHCHECKS_RESTORE_URL: https://hc-ping.com/<uuid-restore>
   ```

3. Aplique com `just k8s-vps-secrets`.

As chaves são `optional: true` nos CronJobs: sem elas, os jobs rodam
normalmente e apenas não pingam. Falha no ping não falha o job (o backup em si
já terminou); o sinal de falha do job continua vindo dos eventos Kubernetes →
Loki → Grafana.

## 2. Monitoração de endpoints públicos (UptimeRobot ou similar)

Para os hostnames públicos (status page e `mcp-gateway`, que não ficam atrás
do Cloudflare Access), use um monitor HTTP externo gratuito — UptimeRobot,
Better Stack, ou os próprios checks HTTP do healthchecks.io:

| Monitor | URL | Esperado |
|---|---|---|
| gateway | `https://mcp-gateway.<domínio>/healthz` | HTTP 200 |
| status page | `https://status.<domínio>/healthz` ¹ | HTTP 200/302 |

¹ Com Cloudflare Access habilitado na status page (Terraform,
`status_page_access_enabled`), um monitor sem credenciais recebe **302 para o
login do Access** — configure o monitor para aceitar 302, ou crie um Access
service token e envie os headers `CF-Access-Client-Id`/`CF-Access-Client-Secret`
no monitor (UptimeRobot e Better Stack suportam headers customizados).

Serviços atrás do Cloudflare Access **não** devem ser monitorados sem service
token: o monitor mediria o uptime da página de login do Cloudflare, não do
serviço.

Intervalo sugerido: 5 minutos. Lembre que cada request a um hostname coberto
pelo KEDA HTTP Add-on **acorda o serviço** (ADR 0016) — aponte monitores para
o gateway/status page, não para cada MCP individual, para não anular o
scale-to-zero.
