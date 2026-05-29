# ADR 0001 — Sleep pattern: workloads default to replicas=0

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto roda em um VPS pessoal de custo fixo. Manter todos os serviços rodando 24/7 desperdiça memória e CPU quando não estão sendo usados. Os serviços (MCPs e BFFs) são stateless e toleram cold start de poucos segundos.

## Decisão

Todos os `Deployment` no `k8s/base` são declarados com `replicas: 0`. Serviços sobem sob demanda via:

- `kubectl scale` manual (scripts `wake-github.sh`, `wake-vos.sh`)
- Overlay local (`replicas-local.yaml`) que sobe os serviços ready para desenvolvimento
- Futuramente: HTTP scale-to-zero ou trigger externo

O padrão `sleep-all` (`just sleep-all`) devolve tudo a zero.

## Consequências

- **Positivo:** custo de recursos no VPS proporcional ao uso real; base de código limpa sem condicionais de ambiente nas replicas
- **Positivo:** o overlay local sobrescreve de forma explícita, tornando visível quais serviços estão ativos em cada ambiente
- **Negativo:** latência de cold start (~5–15s) ao acordar um serviço; aceitável para uso pessoal
- **Negativo:** requer intervenção manual para acordar serviços no VPS; um trigger automático (ex. Cloudflare Worker) seria necessário para zero-touch
