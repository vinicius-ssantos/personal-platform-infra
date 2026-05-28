# VPS setup

Target stack:

- Ubuntu 22.04+
- k3s single-node
- Traefik default ingress
- apps sleeping by default
- database/storage outside the VPS

## Bootstrap

```bash
ansible-playbook -i ansible/inventory/vps.ini ansible/playbooks/bootstrap-vps.yml
```

## Apply Kubernetes overlay

```bash
kubectl apply -k k8s/overlays/vps
```

## Operating model

Use `replicas=0` by default for MCP/BFF apps and wake them when needed.
