# Cloudflare Access

Cloudflare Tunnel and DNS make the platform hostnames reachable. Cloudflare
Access is the first authorization layer in front of those public hostnames.
Service-level bearer/API tokens remain required where the application supports
them.

## Terraform setup

Enable Access in `terraform/cloudflare/terraform.tfvars`:

```hcl
cloudflare_access_enabled = true

cloudflare_access_allowed_emails = [
  "you@example.com",
]

cloudflare_access_allowed_email_domains = []
cloudflare_access_allowed_idps = []

# Optional for automation/non-browser clients.
cloudflare_access_service_token_enabled = true
```

Then apply:

```bash
just terraform-init
just terraform-plan
just terraform-apply
```

Terraform creates one self-hosted Access application per service hostname:

- `mcp-github.<domain>`
- `deploy-mcp.<domain>`
- `social-mcp.<domain>`
- `github-bff.<domain>`
- `vos-mcp.<domain>`
- `vos-bff.<domain>`

When Access is enabled, Terraform requires at least one allowed email, allowed
email domain, or service token. Anonymous internet access is not configured.

### Public edge excluded from Access

`mcp-gateway.<domain>` (the `central-mcp-gateway`) is **intentionally not** behind
Cloudflare Access. It is the ChatGPT-facing OAuth edge and authenticates requests
itself (public bearer token + OAuth); an Access login interstitial would break the
third-party OAuth flow. In Terraform it lives in the `public_services` map, which
gets DNS and tunnel routing but no Access application. Do not add it to
`local.services`.

## Human access

Human users authenticate through Cloudflare Access using the configured identity
provider. Add explicit user emails or allowed email domains in Terraform.

## Automation access

For non-browser clients, enable the service token:

```hcl
cloudflare_access_service_token_enabled = true
```

After apply, store the sensitive outputs immediately in a secret manager:

```bash
terraform -chdir=terraform/cloudflare output -raw cloudflare_access_service_token_client_id
terraform -chdir=terraform/cloudflare output -raw cloudflare_access_service_token_client_secret
```

Clients must send both Cloudflare Access headers plus any application-level
auth header:

```http
CF-Access-Client-Id: <client-id>
CF-Access-Client-Secret: <client-secret>
Authorization: Bearer <service-level-token>
```

Do not commit service token values or application bearer tokens.
