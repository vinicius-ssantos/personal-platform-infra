# ADR 0002 — Storage e bancos de dados fora do cluster

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O VPS é um nó único sem redundância. Rodar bancos de dados (PostgreSQL, Redis) no k3s exigiria volumes persistentes, backup de PVCs, e gestão de StatefulSets — complexidade desproporcional para um projeto pessoal. Serviços gerenciados externos (Supabase, Firebase, Upstash, Cloudflare R2) oferecem durabilidade, backups e interface de administração prontos.

## Decisão

Nenhum banco de dados ou armazenamento persistente é declarado nos manifestos k8s deste repositório. Todo dado persistente vai para serviços externos:

- **Banco relacional / BaaS:** Supabase ou Firebase
- **Object storage:** Cloudflare R2
- **Cache / fila:** Upstash Redis (se necessário)
- **Exceção local:** `mcp-social` usa SQLite via volume Compose apenas em desenvolvimento

Os serviços no cluster são tratados como stateless: podem ser recriados sem perda de dados.

## Consequências

- **Positivo:** elimina risco de perda de dados por falha do nó único; sem gestão de backups de PVC
- **Positivo:** manifests k8s simples (Deployment + Service, sem PVC, PV, StatefulSet)
- **Negativo:** dependência de serviços externos pagos ou com tier gratuito limitado
- **Negativo:** latência de rede entre cluster e storage externo; aceitável para workloads MCP de baixo volume
