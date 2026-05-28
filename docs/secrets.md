# Secrets

Never commit real secrets in plain text.

Recommended approach:

1. Keep `.env.example` committed.
2. Keep `.env` local only.
3. Later add SOPS + age for encrypted structured secrets.

Potential secret files:

```txt
secrets/local.enc.yaml
secrets/vps.enc.yaml
```

Examples of sensitive values:

- GitHub tokens
- MCP bearer tokens
- Cloudflare API token
- Supabase service role key
- Meta/Instagram/Threads tokens
- session/JWT secrets
