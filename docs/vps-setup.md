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
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/vps.ini ansible/playbooks/bootstrap-vps.yml
```

Export the kubeconfig from the VPS, base64-encode it, and save it as the
GitHub Actions secret `VPS_KUBECONFIG` when automated deploys should start
applying `k8s/overlays/vps`.

## Apply Kubernetes overlay

```bash
kubectl apply -k k8s/overlays/vps
```

## Status page

Copy `cloudflare/workers/status-page/wrangler.toml.example` to
`cloudflare/workers/status-page/wrangler.toml`, replace the example domain, and
protect the route with Cloudflare Access before deploying:

```bash
just status-page-deploy
```

## Operating model

Use `replicas=0` by default for MCP/BFF apps and wake them when needed.
