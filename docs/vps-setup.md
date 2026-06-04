# VPS setup

Target stack:

- Ubuntu 22.04+
- k3s single-node
- Traefik default ingress
- apps sleeping by default
- database/storage outside the VPS

## Bootstrap

Provision the VM first:

```bash
cp terraform/vps/terraform.tfvars.example terraform/vps/terraform.tfvars
just terraform-vps-init
just terraform-vps-plan
just terraform-vps-apply
```

Use the `ipv4_address` Terraform output in `ansible/inventory/vps.ini` and in
the Cloudflare Terraform workspace when `target_mode = "vps-ip"`.

Then bootstrap the host:

```bash
# Instalar Ansible collections necessárias primeiro
ansible-galaxy collection install -r ansible/requirements.yml

# Executar bootstrap completo
ansible-playbook -i ansible/inventory/vps.ini ansible/playbooks/bootstrap-vps.yml
```

The VPS bootstrap opens only `80/tcp` and `443/tcp` publicly in UFW. The k3s API
port `6443/tcp` is opened only for explicit `k3s_api_allowed_cidrs` values in
the Ansible inventory or extra vars. Example:

```bash
ansible-playbook -i ansible/inventory/vps.ini ansible/playbooks/bootstrap-vps.yml \
  -e 'k3s_api_allowed_cidrs=["198.51.100.25/32"]'
```

Export the kubeconfig from the VPS, base64-encode it, and save it as the
GitHub Actions secret `VPS_KUBECONFIG` when automated deploys should start
applying `k8s/overlays/vps`.

Also set the `VPS_DOMAIN` GitHub Actions **repository variable** (not a secret —
the domain is not sensitive) to your base domain, e.g. `example.org`. The VPS
overlay carries a `__VPS_DOMAIN__` token instead of a hard-coded domain so the
real domain never lives in git; `deploy-vps.yml` renders it from `VPS_DOMAIN`
before applying. Without this variable the deploy fails fast with a clear error.

Create or update GHCR pull secrets before waking workloads:

```bash
GHCR_USERNAME="<github-username>" \
GHCR_TOKEN="<token-with-read-packages>" \
just create-ghcr-secret
```

Create the runtime `platform-secrets` objects from the encrypted secrets flow
before waking workloads. The deployments reference those Secrets directly; the
base manifests do not contain final token values.

## Apply Kubernetes overlay

The overlay uses a `__VPS_DOMAIN__` token, so render it with your domain before
applying (CI does this automatically from the `VPS_DOMAIN` variable):

```bash
export VPS_DOMAIN=example.org
just k8s-vps-apply          # render + kubectl apply -f -
# or inspect first:
just render-vps             # prints rendered manifests
```

## Status page

Initialize the local Wrangler config, replace the example domain, and protect
the route with Cloudflare Access before deploying:

```bash
just status-page-init
just status-page-deploy
```

## Operating model

Use `replicas=0` by default for MCP/BFF apps and wake them when needed.
