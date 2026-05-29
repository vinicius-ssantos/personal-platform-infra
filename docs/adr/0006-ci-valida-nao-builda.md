# ADR 0006 — CI valida configurações, não builda imagens

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

Este repositório é exclusivamente de infraestrutura: Ansible, Terraform, manifestos k8s e scripts. As imagens dos serviços (MCPs, BFFs) são buildadas e publicadas nos seus respectivos repositórios upstream via GHCR. Incluir builds de imagem aqui criaria acoplamento desnecessário.

## Decisão

O CI deste repositório (`ci.yml`) executa apenas validações de configuração:

1. Sintaxe YAML (todos os `.yml`/`.yaml`)
2. `docker compose config` (valida o Compose sem subir containers)
3. Sintaxe de shell scripts (`bash -n`)
4. Terraform `fmt`, `init -backend=false`, `validate`

O workflow `deploy-vps.yml` aplica manifestos ao cluster VPS no merge para `main` quando `k8s/**` muda — mas não builda nenhuma imagem.

Smoke tests (`just smoke-k3d`, `just smoke-all`) são executados localmente pelo operador, não no CI, pois requerem Docker e k3d.

## Consequências

- **Positivo:** CI rápido (~1–2min) sem necessidade de Docker-in-Docker ou credenciais de registry
- **Positivo:** separação clara de responsabilidades: cada repo de serviço gerencia seu próprio pipeline de build
- **Negativo:** o CI não detecta regressões de runtime (ex. imagem quebrada no GHCR); isso é responsabilidade dos repos upstream
- **Negativo:** smoke tests não são executados automaticamente em PRs; disciplina manual necessária antes de merges que afetam manifestos
