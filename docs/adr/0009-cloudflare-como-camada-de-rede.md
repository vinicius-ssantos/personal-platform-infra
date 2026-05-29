# ADR 0009 — Cloudflare como camada única de rede

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto precisa resolver quatro problemas de rede: DNS para o domínio, exposição de serviços locais à internet (durante desenvolvimento), TLS para todos os endpoints, e hospedagem de frontends estáticos. Resolver cada um com ferramentas diferentes (Route53, ngrok, Certbot, Vercel) aumentaria a superfície de configuração e o número de contas.

## Decisão

Consolidar toda a camada de rede no Cloudflare:

| Necessidade | Solução Cloudflare |
|---|---|
| DNS | Cloudflare DNS (gerenciado via Terraform) |
| Exposição local | Cloudflare Tunnel (`cloudflared`) |
| TLS | Automático pelo proxy Cloudflare |
| Frontends | Cloudflare Pages |

O Terraform neste repositório gerencia apenas recursos Cloudflare. O DNS alterna entre tunnel endpoint (desenvolvimento) e IP do VPS (produção) via variável `target_mode`.

## Consequências

- **Positivo:** TLS automático em todos os endpoints sem Certbot ou cert-manager no cluster
- **Positivo:** Cloudflare Tunnel expõe serviços locais sem abrir portas no roteador ou precisar de IP fixo
- **Positivo:** uma conta, uma API key, uma superfície de configuração
- **Negativo:** vendor lock-in no Cloudflare; migração de DNS + tunnel + pages simultânea seria trabalhosa
- **Negativo:** latência adicional via proxy Cloudflare em todas as requisições (geralmente <10ms; aceitável para uso pessoal)
