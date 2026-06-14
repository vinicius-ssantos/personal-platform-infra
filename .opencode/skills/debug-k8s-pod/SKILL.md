---
name: debug-k8s-pod
description: Use when a Kubernetes pod is crashing, failing healthchecks, or not starting. Systematic debugging workflow for pods in k3d or k3s. Trigger keywords: pod, crash, crashloop, CrashLoopBackOff, failing, healthcheck, pod not starting, debug pod, investigate pod, kubectl describe, kubectl logs.
---

# Debug Kubernetes Pod

## Roteiro de diagnóstico (em ordem)

### 1. Status geral

```bash
kubectl get pods -A
kubectl get pods -n <namespace>
```

### 2. Descrever o pod

```bash
kubectl describe pod -n <namespace> <pod-name>
```

Procurar por:
- **Events** no final: ImagePullBackOff, CrashLoopBackOff, FailedMount, FailedScheduling
- **Conditions**: PodScheduled? Initialized? Ready?
- **Containers**: State (Waiting? Running? Terminated?)

### 3. Logs

```bash
# Logs atuais
kubectl logs -n <namespace> <pod-name>

# Logs do container anterior (se crashou)
kubectl logs -n <namespace> <pod-name> --previous

# Logs com tail
kubectl logs -n <namespace> <pod-name> --tail=50
```

### 4. Causas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `ImagePullBackOff` | Imagem não existe ou credenciais erradas | Verificar image tag no deployment |
| `CrashLoopBackOff` | App crashou na inicialização | Ver logs `--previous`, variáveis de ambiente |
| `FailedMount` | Secret ou ConfigMap não encontrado | Verificar se o Secret/ConfigMap existe no namespace |
| `FailedScheduling` | Sem recursos ou node affinity | Verificar recursos do cluster |
| `Readiness probe failed` | App não está pronto | Verificar se depende de outro serviço não disponível |
| `Liveness probe failed` | App travou ou está lento | Verificar timeout da probe vs tempo de startup |

### 5. Verificações específicas do repo

```bash
# Secrets injetados?
kubectl get secrets -n <namespace>

# ConfigMap existe?
kubectl get configmap -n <namespace>

# PVC montado? (mcp-social)
kubectl get pvc -n <namespace>

# Logs do Loki/Alloy
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy
```

### 6. Smoke test

Depois de corrigir, validar com smoke:

```bash
just smoke-k3d
```

## Para o orquestrador

Se o pod continua falhando após diagnóstico básico, delegue para `infra-engineer` (pode ser problema de config) ou `explorer` (investigação mais profunda).