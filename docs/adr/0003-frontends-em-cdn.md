# ADR 0003 — Frontends hospedados em CDN, nunca no k8s

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

Servir assets estáticos de um nó k3s único significa: sem CDN, sem redundância, SSL manual, e ocupação de recursos no VPS para tráfego que pode ser totalmente descarregado. Plataformas como Cloudflare Pages, Vercel e Netlify oferecem deploy de estáticos com SSL, CDN global e preview deploys sem custo adicional.

## Decisão

Nenhum frontend (SPA, site estático) é declarado nos manifestos k8s deste repositório. Frontends vivem em plataformas dedicadas:

- **Preferido:** Cloudflare Pages (alinhado ao uso de Cloudflare DNS e Tunnel)
- **Alternativas:** Vercel, Netlify

O cluster expõe apenas APIs (MCPs e BFFs). O roteamento frontend → BFF é feito via variável de ambiente `FRONTEND_URL` / `MCP_URL` nos deployments.

## Consequências

- **Positivo:** sem gestão de ingress/TLS para assets estáticos; preview deploys gratuitos por branch
- **Positivo:** libera recursos do VPS exclusivamente para workloads de API
- **Negativo:** adiciona uma plataforma externa no deploy pipeline dos frontends (fora do escopo deste repo)
- **Negativo:** CORS e cookies cross-origin precisam de atenção quando frontend e BFF estão em domínios diferentes
