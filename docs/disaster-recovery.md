# VPS disaster recovery and bootstrap

This runbook describes the minimum data and steps needed to rebuild the personal platform after a local workstation reset, lost kubeconfig, VPS rebuild, or full machine loss.

Do not store real secret values in this repository.

## Recovery inventory

### Must be backed up outside the repo

| Item | Why it matters | Recovery impact if lost |
| --- | --- | --- |
| age private key, usually `~/.age/personal-platform.txt` | decrypts `secrets/*.enc.yaml` | encrypted repo secrets cannot be decrypted |
| Cloudflare API token/account/zone identifiers | manages DNS, tunnel and status page resources | Cloudflare Terraform cannot be applied |
| VPS SSH key and provider access | bootstraps or repairs the VPS | VPS access may need provider console reset |
| GitHub token with package read access | recreates GHCR image pull secrets | pods may fail with image pull errors |
| GitHub Actions secrets values | restores automated VPS deploy | deploy workflow may skip or fail |
| Terraform state backend credentials/state | prevents drift or duplicate resources | Terraform may need import/reconciliation |

### Stored in the repo, but encrypted or declarative

- `secrets/local.enc.yaml`
- `secrets/vps.enc.yaml`
- Kubernetes manifests under `k8s/`
- Terraform code under `terraform/`
- Ansible playbooks and inventories under `ansible/`
- Cloudflare Worker/status page source under `cloudflare/`

### Generated artifacts that can be recreated

- kubeconfig exported from the VPS k3s cluster;
- Kubernetes namespace resources;
- GHCR pull secrets;
- Grafana admin Secret;
- local/k3d clusters;
- Cloudflare tunnel runtime credentials when the Terraform/state path is intact.

## Backup checklist

Run locally and store the output/keys in a password manager or secure offline vault:

```bash
just secrets-backup
```

Also record where these values live:

- GitHub repository secrets, especially `VPS_KUBECONFIG`.
- Cloudflare account ID, zone ID and API token location.
- VPS provider account and SSH key location.
- Terraform backend/state location.
- GHCR package read token location.

## Local workstation reset

1. Clone the repository.
2. Restore the age private key to `~/.age/personal-platform.txt`.
3. Install tools:

```bash
just bootstrap-local
```

4. Verify secrets can be opened:

```bash
just secrets-edit-local
just secrets-edit-vps
```

5. Recreate local env files and validate:

```bash
just env-init
just check-env
```

6. Rebuild local Kubernetes if needed:

```bash
just smoke-k3d
just k3d-secrets
```

## VPS rebuild

Use this when the VPS was recreated from scratch.

1. Update `ansible/inventory/vps.ini` with the new host/IP.
2. Bootstrap the machine:

```bash
just bootstrap-vps
```

3. Recreate or verify Cloudflare resources:

```bash
just terraform-init
just terraform-plan
just terraform-apply
```

4. Export the new k3s kubeconfig from the VPS and store it locally only long enough to update automation.
5. Base64-encode the kubeconfig and update GitHub Actions secret `VPS_KUBECONFIG`.
6. Apply Kubernetes resources:

```bash
just k8s-vps-apply
```

7. Recreate GHCR pull secrets in the required namespaces:

```bash
just create-ghcr-secret
```

Then run the printed `kubectl create secret docker-registry ...` command for each namespace that pulls private GHCR images.

8. Recreate the Grafana admin Secret without committing credentials:

```bash
TARGET_ENV=vps GRAFANA_ADMIN_PASSWORD='<from-secure-vault>' just grafana-secret
```

9. Wake only the workloads needed for validation:

```bash
just wake-github
just wake-deploy
just wake-social
just wake-vos
```

10. Validate platform health:

```bash
just status
just status-public
just smoke-logs
```

## Lost kubeconfig

If the VPS still exists and SSH works, regenerate/export kubeconfig from the VPS k3s installation and update the GitHub Actions `VPS_KUBECONFIG` secret.

After updating the GitHub secret, validate that the deploy workflow no longer skips VPS deployment on the next `k8s/**` change, or run a manual deployment path with:

```bash
just k8s-vps-apply
```

## Lost age private key

If the age private key is lost and no backup exists, encrypted files in `secrets/*.enc.yaml` cannot be decrypted.

Recovery path:

1. Generate a new age keypair.
2. Recreate secret values from the password manager/provider dashboards.
3. Re-encrypt `secrets/local.enc.yaml` and `secrets/vps.enc.yaml` to the new public key.
4. Update documentation and backup location.
5. Run:

```bash
just secrets-backup
```

## Lost GHCR pull secret

The Kubernetes pull secret can be recreated from a GitHub token with package read access.

```bash
just create-ghcr-secret
```

Apply the printed command for each namespace. Then restart failed deployments or let Kubernetes retry image pulls.

## Lost Cloudflare tunnel or DNS state

1. Confirm Terraform state is available.
2. Re-run:

```bash
just terraform-plan
just terraform-apply
```

3. If Terraform state is lost but Cloudflare resources still exist, import or reconcile them before applying to avoid duplicate DNS/tunnel resources.
4. Validate public endpoints:

```bash
just status-public
```

## Post-recovery validation

Minimum validation after any rebuild:

```bash
just check-env
just k8s-vps-apply
just status
just status-public
just smoke-logs
```

If KEDA HTTP Add-on is enabled for the pilot workloads:

```bash
just keda-http-install
just smoke-keda-http
```

See `docs/lifecycle.md` before manually scaling KEDA-managed workloads.

## What not to do

- Do not commit decrypted secrets or kubeconfig files.
- Do not commit real Grafana credentials.
- Do not expose Grafana publicly as part of recovery.
- Do not run destructive Terraform applies if state is missing and resources already exist; import/reconcile first.
- Do not mix manual wake/sleep with KEDA-managed workloads except during break-glass recovery.
