# ADR 0007 — Kustomize em vez de Helm

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto precisa de um mecanismo para diferenciar manifestos entre ambientes (local vs VPS) sem duplicar YAML. As opções consideradas foram:

| Opção | Template engine | Releases/rollback | Curva de aprendizado |
|---|---|---|---|
| Helm | sim (Go templates) | sim | alta |
| **Kustomize** | não (patches/overlays) | não | baixa |
| Jsonnet | sim | não | muito alta |
| Plain kubectl + scripts | não | não | mínima |

## Decisão

Usar Kustomize com padrão `base + overlays`:

- `k8s/base/` — manifestos canônicos compartilhados por todos os ambientes
- `k8s/overlays/local/` — patches para desenvolvimento (réplicas, configurações locais)
- `k8s/overlays/vps/` — patches para produção

Nenhum template engine é necessário: as diferenças entre ambientes são expressas como patches estratégicos (ex. `replicas-local.yaml`).

## Consequências

- **Positivo:** manifestos base são YAML puro e legíveis sem conhecimento de Helm; sem `{{ }}` nos arquivos
- **Positivo:** sem Tiller, sem releases, sem `helm upgrade` — `kubectl apply -k` é suficiente
- **Positivo:** nativo no `kubectl` desde 1.14; sem dependência adicional
- **Negativo:** sem mecanismo de rollback de release integrado (Helm mantém histórico de deployments)
- **Negativo:** configurações complexas com muitas variáveis ficam verbosas em patches; Helm seria mais ergonômico nesse caso
