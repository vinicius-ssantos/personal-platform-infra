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

# 3. Create an encrypted file from the example
cp secrets/local.enc.yaml.example secrets/local.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/local.enc.yaml

cp secrets/vps.enc.yaml.example secrets/vps.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/vps.enc.yaml

# 4. Edit secrets
just secrets-edit-local
just secrets-edit-vps
```

### Editing an encrypted file

```bash
just secrets-edit-local   # opens secrets/local.enc.yaml in $EDITOR
just secrets-edit-vps     # opens secrets/vps.enc.yaml in $EDITOR
```

### Decrypt for use

```bash
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -d secrets/local.enc.yaml
```

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
