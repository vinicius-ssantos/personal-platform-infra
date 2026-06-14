---
name: secrets-management
description: Use when working with secrets, SOPS, age encryption, or environment variables. Covers encrypting, decrypting, editing secrets, and creating local/VPS secrets files. Trigger keywords: secrets, SOPS, age, encrypt, decrypt, env, .env, edit secrets, secrets-edit, k3d-secrets.
---

# Secrets Management

## Ferramentas

- **SOPS**: Mozilla Secrets OPerationS — encrypt/decrypt YAML/JSON
- **age**: encryption tool — chave privada em `~/.age/personal-platform.txt`

## Workflow

### Editar secrets locais

```bash
just secrets-edit-local
```

Abre o arquivo `secrets/platform-secrets-local.enc.yaml` descriptografado no editor.

### Editar secrets VPS

```bash
just secrets-edit-vps
```

### Injeta secrets no k3d local

```bash
just k3d-secrets
```

Lê `.env` e cria Kubernetes Secrets no cluster k3d.

### Criar arquivo de secrets do zero

1. Criar `secrets/<nome>.enc.yaml.example` com template (placeholders)
2. Copiar pra `secrets/<nome>.enc.yaml` (sem .example)
3. Rodar `sops --encrypt --age <age_public_key> -i secrets/<nome>.enc.yaml`
4. Comitar `.enc.yaml.example` apenas — `.enc.yaml` vai no `.gitignore`

## Verificação

```bash
# Ver chave age pública
age-keygen -y ~/.age/personal-platform.txt

# Verificar se SOPS consegue decriptar
sops -d secrets/platform-secrets-local.enc.yaml | head -5
```

## Armadilhas

- `.enc.yaml` NUNCA é commitado — `.gitignore` já bloqueia
- Sem a chave age em `~/.age/personal-platform.txt`, `just secrets-edit-*` não funciona
- Secrets de runtime no k8s vão em overlays ou secrets SOPS, não no base
- Grafana admin Secret no namespace `monitoring` precisa ser criado manualmente no VPS