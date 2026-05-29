# ADR 0010 — Namespaces por domínio funcional

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

Com 6 serviços no cluster, a escolha de organização de namespaces era: tudo em `default`, um namespace único por projeto (`personal-platform`), ou namespaces por domínio funcional. A escolha afeta futuro RBAC, NetworkPolicy, e legibilidade de `kubectl get pods -A`.

## Decisão

Três namespaces por domínio funcional:

| Namespace | Serviços |
|---|---|
| `mcp` | github-unified-mcp, deploy-orchestrator-mcp, mcp-social |
| `bff` | github-unified-mcp-bff, vos-studio-bff |
| `vos` | vos-studio-mcp |

Serviços de suporte futuros (ex. Redis, observabilidade) receberão namespace próprio.

## Consequências

- **Positivo:** `kubectl get pods -n mcp` isola visibilidade por camada; `-A` ainda mostra tudo
- **Positivo:** base para RBAC granular no futuro: um service account por namespace, permissões mínimas por domínio
- **Positivo:** NetworkPolicy pode restringir tráfego por namespace quando necessário
- **Negativo:** comunicação entre namespaces (ex. BFF chamando MCP) requer FQDN: `github-unified-mcp.mcp.svc.cluster.local` em vez de só `github-unified-mcp`
- **Negativo:** pequeno overhead de gestão vs namespace único; aceitável dado o benefício de isolamento
