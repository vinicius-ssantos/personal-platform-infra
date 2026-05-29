# ADR 0005 — k3d para desenvolvimento local, k3s para VPS

**Data:** 2026-05-29
**Status:** Accepted

## Contexto

O projeto precisa de paridade entre o ambiente de desenvolvimento e produção (VPS). As opções para runtime Kubernetes local avaliadas foram kind, minikube, k3d e Docker Compose puro.

| Opção | Paridade com k3s | Overhead | Windows/WSL2 |
|---|---|---|---|
| Docker Compose | baixa | mínimo | bom |
| kind | média | médio | bom |
| minikube | média | alto | problemático |
| **k3d** | alta (mesmo k3s) | baixo | bom |

## Decisão

- **Local:** k3d wrappeia k3s em containers Docker, produzindo um cluster localmente idêntico ao VPS. Traefik é desabilitado no overlay local (não necessário para smoke tests via port-forward).
- **VPS:** k3s bare-metal single-node com Traefik nativo como ingress controller.

Os mesmos manifestos Kustomize (`k8s/base`) são usados em ambos; diferenças são expressas apenas nos overlays (`k8s/overlays/local` e `k8s/overlays/vps`).

Docker Compose permanece como caminho alternativo para iteração rápida sem Kubernetes.

## Consequências

- **Positivo:** bugs de manifesto são capturados localmente antes de chegar ao VPS
- **Positivo:** `just smoke-k3d` valida o path k8s completo em ambiente local
- **Negativo:** k3d requer Docker Desktop rodando; adiciona ~200–400MB de overhead vs Compose puro
- **Negativo:** comportamentos específicos de k3s (ex. resolução de DNS interna, LoadBalancer) diferem levemente de k3d; casos extremos podem não ser reprodutíveis localmente
