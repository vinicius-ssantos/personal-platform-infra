# personal-platform-infra

Infraestrutura pessoal para rodar MCPs, BFFs e serviços auxiliares em dois ambientes:

- **Local**: Windows + WSL2 Ubuntu + Docker Compose/k3d + Cloudflare Tunnel
- **VPS**: Ubuntu + k3s + Traefik

## Objetivo

Centralizar a automação de:

- Terraform para Cloudflare, DNS, Tunnel e Pages
- Ansible para bootstrap local e VPS
- Docker Compose para modo local simples
- k3d/k3s para modo Kubernetes
- scripts de start/stop/wake/sleep

## Apps gerenciados

- `github-unified-mcp`
- `deploy-orchestrator-mcp`
- `mcp-social`
- `github-unified-mcp-bff`
- `vos-studio-mcp`
- `vos-studio-bff`

Veja a [matriz de integracao de servicos](docs/service-integration-matrix.md) para o status de cada servico.

## Princípios

- Frontends ficam fora da VPS, preferencialmente em Cloudflare Pages/Vercel/Netlify.
- Banco e storage ficam fora da VPS, preferencialmente Supabase/Firebase/R2.
- Serviços podem dormir por padrão e acordar sob demanda.
- Secrets reais nunca devem ser commitados abertos.
- Local e VPS usam a mesma estrutura base, mudando apenas overlays/configurações.

## Começo rápido

```bash
# 1) instalar ferramentas no WSL2
just bootstrap-local

# 2) modo local simples
just compose-up
just compose-down

# 3) modo Kubernetes local
just k8s-local-up
just k8s-local-down

# 4) expor via Cloudflare Tunnel
just tunnel
```

## Estrutura

```txt
ansible/      Bootstrap local e VPS
terraform/   Cloudflare, DNS, Tunnel e Pages
compose/     Modo local simples com Docker Compose
k8s/         Manifests Kubernetes base + overlays local/vps
scripts/     Operação diária: start, stop, tunnel, wake/sleep
docs/        Arquitetura, setup e runbooks
secrets/     Exemplos e arquivos criptografados futuramente
```

## Status

Este repo começou como esqueleto de infraestrutura. Os manifests e módulos devem evoluir em pequenos commits incrementais.
