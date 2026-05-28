# Local setup

Expected local stack:

- Windows 11
- WSL2 Ubuntu
- Docker Desktop with WSL integration
- Ansible
- Terraform
- k3d
- kubectl
- helm
- cloudflared
- just

## Bootstrap

```bash
just bootstrap-local
```

## Compose mode

```bash
cp .env.example .env
just compose-up
just compose-logs
just compose-down
```

## Kubernetes mode

```bash
just k8s-local-up
kubectl get pods -A
just k8s-local-down
```

## Expose local services

```bash
just tunnel
```
