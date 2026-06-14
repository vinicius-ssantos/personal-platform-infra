---
name: adicionar-servico
description: Use when the user wants to add or onboard a new service to the platform. Covers k8s manifests, compose, env.example, smoke tests, Justfile recipes, and docs. Trigger keywords: novo serviço, new service, adicionar serviço, onboard, add service.
---

# Adicionar novo serviço

Passo a passo para adicionar um novo serviço à plataforma.

## 1. k8s manifests

Criar `k8s/base/apps/<nome>/` com:

- `deployment.yaml` — deployment com probes, resources, labels `app`/`version`/`managed-by`, `replicas: 0`
- `service.yaml` — ClusterIP service
- `configmap.yaml` — se necessário (config não sensível)
- `kustomization.yaml` — com `namePrefix`, labels comuns e resources list

Adicionar o novo diretório em `k8s/base/kustomization.yaml` no `resources`.

Se o serviço precisa de overlay local (replica > 0 em dev), criar patch em `k8s/overlays/local/`. Se for dormir no VPS, não precisa de overlay vps — replicas=0 na base cuida disso.

## 2. Docker Compose

Adicionar serviço em `compose/docker-compose.yml` com:

- `profiles` adequado
- Porta host (ver tabela de portas no CLAUDE.md)
- `healthcheck` compatível com o endpoint do serviço
- Variáveis de ambiente necessárias

## 3. .env.example

Adicionar variáveis de ambiente do novo serviço em `.env.example`.

## 4. Smoke script

Criar `scripts/smoke-<nome>.sh` com:

```bash
#!/bin/bash
set -euo pipefail

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; }

healthcheck() {
  local url=$1
  local retries=10
  until curl -sf "$url" > /dev/null 2>&1; do
    retries=$((retries - 1))
    [ $retries -eq 0 ] && error "Timeout: $url" && exit 1
    sleep 2
  done
  info "OK: $url"
}

healthcheck "http://localhost:<porta>/healthz"
info "Todos os healthchecks passaram."
```

## 5. Justfile

Adicionar recipe no `Justfile` seguindo o padrão existente.

## 6. Documentação

Atualizar:
- `docs/service-integration-matrix.md`
- `docs/runbook.md` se aplicável
- Tabela de serviços no `CLAUDE.md`