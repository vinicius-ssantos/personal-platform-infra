# ADR 0013 — VPS single-node sem alta disponibilidade

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

Kubernetes com HA requer no mínimo 3 nós (ou 3 control planes). Para uso pessoal com workloads não-críticos (MCPs e BFFs de uso próprio), o custo de múltiplos nós VPS não se justifica. A alternativa é aceitar single-point-of-failure no VPS.

## Decisão

Rodar k3s em modo single-node: um servidor, zero agents. Sem etcd externo, sem control plane redundante.

Implicações aceitas:
- Manutenção do VPS (updates de SO, reboot) causa downtime de todos os serviços
- Falha do VPS = downtime completo até recuperação manual ou reboot automático do provider
- Sem `PodDisruptionBudget` necessário; sem draining de nó

Mitigação: os serviços são stateless e o storage é externo (ADR 0002), então um restart do nó recupera o estado completo em segundos sem perda de dados.

## Consequências

- **Positivo:** custo de um único VPS (~$5–10/mês) vs cluster multi-nó ($30+/mês)
- **Positivo:** operação simples: sem gestão de quorum, sem etcd backup, sem node drain
- **Negativo:** SLA efetivo é o uptime do VPS provider; sem failover automático
- **Negativo:** upgrades de k3s ou do SO requerem downtime planejado (aceitável para uso pessoal)
- **Neutro:** se a criticidade dos serviços aumentar no futuro, migrar para multi-nó requer apenas adicionar agentes ao k3s e mover para overlay com replicas > 1
