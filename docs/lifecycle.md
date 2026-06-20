# Runtime lifecycle ownership

Este documento define quem controla réplicas Kubernetes em cada ambiente e como diagnosticar e recuperar quando o controle esperado não está funcionando.

## Princípio geral

Apenas um controlador deve ser dono das réplicas de um workload por vez.

Um workload está sempre em um destes três modos:

| Modo | Quem controla | Como identificar |
|---|---|---|
| **Manual-managed** | Operador via `just wake-*`, `just sleep-all`, ou `kubectl scale` | Nenhum `ScaledObject` KEDA associado ao deployment |
| **Overlay-managed** | Valores do Kustomize overlay definem a contagem desejada | Deployment aplicado com `kubectl apply -k` sem KEDA |
| **KEDA-managed** | KEDA HTTP Add-on controla scale-from-zero e cooldown | `ScaledObject` e `InterceptorRoute` existem para o deployment |

Não misture comandos manuais de scale com workloads KEDA-managed durante operação normal.

## Ambiente: Local / k3d

**Modo:** Manual/Overlay-managed

O overlay local (`k8s/overlays/local`) define réplicas=1 para todos os serviços prontos. KEDA não é o controlador padrão localmente.

```bash
# Subir cluster e aplicar overlay (réplicas locais ativas)
just k8s-local-up

# Acordar serviço específico
just wake-github
just wake-vos

# Colocar tudo para dormir
just sleep-all

# Restart sem troca de imagem (ortogonal à ownership de réplicas)
just rollout-restart all

# O patch de graceful shutdown tambem cobre monitoring, mas rollout-restart all
# atinge apenas os apps principais (mcp, bff, vos). Para monitoring:
# kubectl rollout restart deploy -n monitoring --all

# Derrubar cluster
just k8s-local-down
```

**Verificar estado atual:**

```bash
kubectl get deployments -A
kubectl get pods -A
```

## Ambiente: VPS — sem KEDA

**Modo:** Manual-managed

O overlay VPS (`k8s/overlays/vps`) mantém réplicas=0 por padrão (ADR 0001). Operadores acordam serviços sob demanda.

```bash
# Acordar grupos de serviços
just wake-github    # github-unified-mcp + github-unified-mcp-bff
just wake-vos       # vos-studio-mcp + vos-studio-bff
just wake-deploy    # deploy-orchestrator-mcp
just wake-social    # mcp-social
just wake-all       # todos acima

# Colocar tudo para dormir
just sleep-all
```

**Verificar réplicas atuais:**

```bash
kubectl get deployments -A --no-headers \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'
```

## Ambiente: VPS — com KEDA HTTP Add-on

**Modo:** KEDA-managed (apenas workloads do piloto)

Quando o piloto KEDA está ativo, tráfego deve passar pelo interceptor do KEDA, não diretamente pelo serviço. O KEDA escala o deployment de zero quando recebe tráfego e o dorme após o cooldown (600 segundos de inatividade).

**Workloads do piloto atual:**

- `github-unified-mcp` (namespace: `mcp`)
- `github-unified-mcp-bff` (namespace: `bff`)

**Verificar se KEDA está ativo para um workload:**

```bash
kubectl get scaledobject -n mcp
kubectl get scaledobject -n bff
kubectl get interceptorroute -n mcp
kubectl get interceptorroute -n bff
```

**Instalar o piloto:**

```bash
just keda-http-install
just smoke-keda-http
```

**Não use** `just wake-github` ou `just sleep-all` para workloads KEDA-managed durante operação normal. Esses comandos escalam diretamente e entram em conflito com o controlador KEDA.

## Tabela de decisão do operador

| Ambiente | Estado do workload | Dono das réplicas | Comando normal |
|---|---|---|---|
| local/k3d | Desenvolvimento local | overlay/manual | `just smoke-k3d`, `just wake-*`, `just sleep-all` |
| VPS | Não onboardado ao KEDA | manual | `just wake-*`, `just sleep-all` |
| VPS | Onboardado ao KEDA HTTP Add-on | KEDA | enviar tráfego pelo interceptor KEDA |
| VPS | Break-glass / incidente | operador | `kubectl scale` direto, depois restaurar dono pretendido |

## Diagnóstico: serviço não responde

### 1. Verificar se o pod existe e está healthy

```bash
# Substitua <ns> e <nome> conforme necessário
kubectl get pods -n <ns> -l app=<nome>
kubectl describe pod -n <ns> <pod-name>
kubectl logs -n <ns> deploy/<nome> --tail=50
```

### 2. Verificar réplicas

```bash
kubectl get deployment <nome> -n <ns> -o jsonpath='{.spec.replicas}'
```

Se for 0: o serviço está dormindo. Use `just wake-<grupo>` ou `kubectl scale`.

### 3. Verificar se é KEDA-managed e o interceptor está vivo

```bash
kubectl get scaledobject <nome> -n <ns>
kubectl get pods -n keda -l app.kubernetes.io/name=keda-add-ons-http-interceptor
```

Se o interceptor não estiver running, o tráfego não vai acordar o serviço. Reinstale:

```bash
just keda-http-install
```

### 4. Verificar secrets

```bash
kubectl get secret platform-secrets -n <ns>
# Se não existir:
just k3d-secrets          # local/k3d
# ou (VPS):
kubectl create secret generic platform-secrets -n <ns> --from-literal=...
```

### 5. Verificar imagem pull

```bash
kubectl describe pod -n <ns> <pod-name> | grep -A5 "Events:"
# "ImagePullBackOff" = problema com GHCR pull secret
just create-ghcr-secret
```

## Break-glass: forçar escala manual em workload KEDA-managed

Use apenas durante incidentes. Após recovery, restaure o controle KEDA.

```bash
# Escalar manualmente (break-glass)
kubectl scale deployment/github-unified-mcp -n mcp --replicas=1

# Após recovery, confirme que o ScaledObject ainda existe
kubectl get scaledobject github-unified-mcp -n mcp

# Se o ScaledObject foi removido acidentalmente, reaplicar
kubectl apply -k k8s/addons/keda-http/pilot
```

Documente o break-glass: o quê aconteceu, quando, e o que foi restaurado.

## Política de scripts

Scripts manuais são seguros para workloads não-KEDA.

Quando um script pode tocar um workload KEDA-managed, ele deve:
- Pular esse workload por padrão, ou
- Imprimir um aviso claro de que KEDA é o dono do ciclo de vida

Expandir KEDA para serviços adicionais requer atualizar este documento e os manifestos do piloto KEDA na mesma mudança.

## Referências

- [ADR 0001](adr/0001-sleep-pattern-replicas-zero.md) — sleep pattern
- [ADR 0016](adr/0016-scale-to-zero-via-keda-http-add-on.md) — KEDA HTTP Add-on
- `k8s/addons/keda-http/pilot/` — manifestos do piloto
- `scripts/keda-http-install.sh` — instalação
- `scripts/smoke-keda-http.sh` — validação
