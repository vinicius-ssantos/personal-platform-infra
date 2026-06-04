# Secrets

Never commit real secrets in plain text.

## Strategy

1. Keep `.env.example` committed with placeholder values.
2. Keep `.env` local only — it is in `.gitignore` and must never be committed.
3. Structured secrets for k8s use SOPS + age encryption in `secrets/*.enc.yaml`.
4. The `.sops.yaml` at the repo root declares which age public key encrypts each file.

## Secret files

| File | Purpose | Committed? |
|---|---|---|
| `.env` | Local Compose secrets | No — gitignored |
| `secrets/local.enc.yaml` | k8s secrets for local/k3d | No — gitignored |
| `secrets/vps.enc.yaml` | k8s secrets for VPS/k3s | No — gitignored |
| `secrets/local.enc.yaml.example` | Template (no real values) | Yes |
| `secrets/vps.enc.yaml.example` | Template (no real values) | Yes |

## Sensitive values

- `GITHUB_TOKEN` — GitHub PAT (scopes: `repo`, `read:packages`)
- `MCP_BEARER_TOKEN` — bearer token for MCP auth; generate with `openssl rand -hex 32`
- `MCP_SERVER_API_KEY` — API key for deploy-orchestrator; generate with `openssl rand -hex 32`
- `SOCIAL_MCP_ACCESS_TOKEN` — platform token for mcp-social
- `CLOUDFLARE_API_TOKEN` — Terraform Cloudflare provider
- `VPS_KUBECONFIG` — base64-encoded kubeconfig for GitHub Actions deploy
- Supabase service role key (if added later)
- Session/JWT secrets

## SOPS + age workflow

### First-time setup

```bash
# 1. Generate a local age key
age-keygen -o ~/.age/personal-platform.txt
# Output: Public key: age1...

# 2. Register the public key in .sops.yaml (replace placeholder)
# Edit .sops.yaml and replace age1REPLACE_WITH_YOUR_LOCAL_AGE_PUBLIC_KEY

# 3. Verify SOPS/age is ready before creating encrypted files
just secrets-check

# 4. Create an encrypted file from the example
cp secrets/local.enc.yaml.example secrets/local.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/local.enc.yaml

cp secrets/vps.enc.yaml.example secrets/vps.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/vps.enc.yaml

# 5. Edit secrets
just secrets-edit-local
just secrets-edit-vps
```

`just secrets-check` fails early when `.sops.yaml` still contains placeholder
age recipients or when the configured age private key file is missing. It does
not decrypt or print secret values.

### Editing an encrypted file

```bash
just secrets-edit-local   # opens secrets/local.enc.yaml in $EDITOR
just secrets-edit-vps     # opens secrets/vps.enc.yaml in $EDITOR
```

### Decrypt for use

```bash
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -d secrets/local.enc.yaml
```

### VPS platform-secrets (declarative, applied to the cluster)

The runtime `platform-secrets` objects for the VPS (referenced by the
deployments in namespaces `mcp`, `bff` and `vos`) are managed as SOPS-encrypted
Kubernetes Secret manifests. They are **not** part of the kustomize overlay —
plain `kubectl apply -k` cannot decrypt SOPS — so they are applied with a
dedicated decrypt step.

```bash
# 1. Create the encrypted file from the template and fill in real values
cp secrets/platform-secrets-vps.enc.yaml.example secrets/platform-secrets-vps.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/platform-secrets-vps.enc.yaml

# 2. Edit later
just secrets-edit-vps-k8s

# 3. Apply to the VPS cluster (kubeconfig must point at the VPS, age key present)
just k8s-vps-secrets        # = sops --decrypt ... | kubectl apply -f -
```

`secrets/platform-secrets-vps.enc.yaml` is gitignored; only the `.example`
template is committed. Apply the Secrets before waking workloads — the
deployments reference them by name.

### Checking your age public key

```bash
just secrets-backup
```

## Age key backup — critical

> **Losing the age private key means permanent loss of access to all encrypted secrets.**
> There is no recovery path without the private key.

The private key lives at `~/.age/personal-platform.txt`. Back it up before using SOPS.

### Backup options (choose one or more)

**Option A — Password manager (recommended)**
Copy the full contents of `~/.age/personal-platform.txt` into a secure note in
Bitwarden, 1Password, or equivalent. Label it `personal-platform age key`.

**Option B — Paper key**
Print the key and store it in a physically secure location.

**Option C — Encrypted cloud storage**
Encrypt the key with a strong passphrase before uploading:
```bash
age -p ~/.age/personal-platform.txt > personal-platform.age.enc
# Upload personal-platform.age.enc to private cloud storage
```

### Backup checklist

- [ ] Generate age key with `age-keygen`
- [ ] Copy public key into `.sops.yaml`
- [ ] Back up **private key** via at least one option above
- [ ] Verify backup by restoring the key on a second device
- [ ] Never commit `~/.age/personal-platform.txt` to any repository

### Recovery after key loss

Recovery is not possible. Prevention is the only option. If the key is lost:
1. Generate a new key pair
2. Re-create all secret values manually (rotate all tokens)
3. Re-encrypt with the new key
4. Update `.sops.yaml` with the new public key

## Pre-commit protection

Install gitleaks to catch accidental secret commits before they happen:

```bash
just hooks-install
```

This runs `gitleaks` on every `git commit` to detect token patterns in the diff.

## GHCR pull secrets

Kubernetes workloads use `platform-puller` service accounts with the
`ghcr-pull-secret` image pull secret in `mcp`, `bff` and `vos`. Create or update
that secret idempotently with:

```bash
GHCR_USERNAME="<github-username>" \
GHCR_TOKEN="<token-with-read-packages>" \
just create-ghcr-secret
```

The helper creates namespaces when missing, applies the Docker registry secret
with `kubectl apply`, and does not echo the token.

## Kubernetes runtime secrets

Deployments reference a `platform-secrets` Secret instead of carrying token
values directly in `k8s/base`.

Expected keys:

| Namespace | Secret | Keys |
|---|---|---|
| `mcp` | `platform-secrets` | `GITHUB_TOKEN`, `MCP_BEARER_TOKEN`, `MCP_SERVER_API_KEY`, `SOCIAL_MCP_ACCESS_TOKEN` |
| `bff` | `platform-secrets` | `MCP_TOKEN` |
| `vos` | `platform-secrets` | reserved for future VOS sensitive values |

For local/k3d smoke tests, `k8s/overlays/local/platform-secrets-local.yaml`
provides placeholder values so pods can start. To replace them with real local
values from `.env`, run:

```bash
just k3d-secrets
```

For VPS, create equivalent `platform-secrets` objects from the encrypted
secrets flow before waking workloads. Do not commit decrypted Secret manifests.
