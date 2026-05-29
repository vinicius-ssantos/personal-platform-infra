# Secrets

Never commit real secrets in plain text.

## Layers

| Layer | File | Usage |
|---|---|---|
| Quick local dev | `.env` (uncommitted) | Docker Compose only |
| Encrypted local | `secrets/local.enc.yaml` | SOPS + age, safe to commit |
| Encrypted VPS | `secrets/vps.enc.yaml` | SOPS + age, safe to commit |

## SOPS + age setup

### 1. Generate an age key pair

```bash
age-keygen -o ~/.age/personal-platform.txt
# outputs: Public key: age1...
```

### 2. Register the public key in `.sops.yaml`

Edit `.sops.yaml` and replace `age1REPLACE_WITH_YOUR_LOCAL_AGE_PUBLIC_KEY` with
the public key printed above. Use a different key pair for VPS if desired.

### 3. Create an encrypted file from the example

```bash
# local
cp secrets/local.enc.yaml.example secrets/local.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/local.enc.yaml

# vps
cp secrets/vps.enc.yaml.example secrets/vps.enc.yaml
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -e -i secrets/vps.enc.yaml
```

### 4. Edit secrets

```bash
just secrets-edit-local
just secrets-edit-vps
```

### 5. Decrypt for use

```bash
SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt sops -d secrets/local.enc.yaml
```

## Justfile recipes

```bash
just secrets-edit-local   # open local.enc.yaml in $EDITOR via sops
just secrets-edit-vps     # open vps.enc.yaml in $EDITOR via sops
```

The recipes expect `SOPS_AGE_KEY_FILE` to be set in the environment or in `.env`.

## Sensitive values managed here

- GitHub tokens
- MCP bearer tokens
- Cloudflare API token, account ID, zone ID, tunnel token
- Social MCP access token
- VPS kubeconfig (for CI/CD deploy workflow)
- Supabase service role key (if added later)
- Session/JWT secrets
