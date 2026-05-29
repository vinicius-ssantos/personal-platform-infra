# ADR 0012 — Deploy VPS automatizado via GitHub Actions

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

Após um merge para `main` que altera manifestos k8s, o cluster VPS precisa receber o `kubectl apply`. As alternativas consideradas foram: SSH manual + kubectl, ArgoCD/Flux (GitOps controllers), e GitHub Actions com kubeconfig.

| Opção | Automático | Complexidade | Requisito no cluster |
|---|---|---|---|
| SSH manual | não | baixa | nenhum |
| ArgoCD / Flux | sim | alta | controller no cluster |
| **GitHub Actions** | sim | baixa | kubeconfig como secret |

ArgoCD/Flux são robustos mas requerem um controller rodando no cluster, ocupando recursos e adicionando superfície de operação. Para um VPS pessoal com deploys pouco frequentes, o overhead não se justifica.

## Decisão

Usar GitHub Actions (`deploy-vps.yml`) que dispara em push para `main` quando arquivos em `k8s/**` mudam:

1. Decodifica `VPS_KUBECONFIG` (base64) do GitHub Secret para `~/.kube/config`
2. Verifica conectividade com `kubectl cluster-info`
3. Aplica `kubectl apply -k k8s/overlays/vps`

O kubeconfig é armazenado como GitHub Secret (não encriptado no repo); para adicionar ao repo, usar `secrets/vps.enc.yaml` via SOPS.

## Consequências

- **Positivo:** zero infraestrutura adicional no cluster; sem ArgoCD, sem Flux
- **Positivo:** deploy auditável no histórico de Actions do GitHub
- **Positivo:** só dispara quando `k8s/**` muda; PRs que alteram apenas docs não triggeram deploy
- **Negativo:** sem reconciliação contínua: se o estado do cluster divergir manualmente, o CI não detecta até o próximo push
- **Negativo:** `VPS_KUBECONFIG` precisa ser rotacionado manualmente quando o kubeconfig do k3s muda
