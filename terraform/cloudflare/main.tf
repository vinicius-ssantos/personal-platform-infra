terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ---------------------------------------------------------------------------
# Cloudflare Tunnel (only created when target_mode = "local-tunnel")
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared" "platform" {
  count = local.use_tunnel ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "personal-platform"
  secret     = var.tunnel_secret

  lifecycle {
    precondition {
      condition     = var.tunnel_secret != null
      error_message = "tunnel_secret is required when target_mode is local-tunnel."
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "platform" {
  count = local.use_tunnel ? 1 : 0

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.platform[0].id

  config {
    dynamic "ingress_rule" {
      for_each = local.all_services
      content {
        hostname = "${ingress_rule.value.subdomain}.${var.domain}"
        service  = ingress_rule.value.backend
      }
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ---------------------------------------------------------------------------
# DNS records — one per service
# ---------------------------------------------------------------------------

locals {
  services = {
    mcp_github = {
      subdomain = "mcp-github"
      backend   = "http://localhost:8765"
    }
    # Local tunnel backends target Compose host ports, not container-internal ports.
    deploy_mcp = {
      subdomain = "deploy-mcp"
      backend   = "http://localhost:8001"
    }
    social_mcp = {
      subdomain = "social-mcp"
      backend   = "http://localhost:8080"
    }
    github_bff = {
      subdomain = "github-bff"
      backend   = "http://localhost:8010"
    }
    vos_mcp = {
      subdomain = "vos-mcp"
      backend   = "http://localhost:8020"
    }
    vos_bff = {
      subdomain = "vos-bff"
      backend   = "http://localhost:8030"
    }
  }

  # Public edge services. The central MCP gateway is the ChatGPT-facing OAuth
  # endpoint and runs its own bearer/OAuth authentication, so it gets DNS and
  # tunnel routing but is intentionally NOT placed behind Cloudflare Access
  # (an Access login interstitial would break the third-party OAuth flow).
  public_services = {
    mcp_gateway = {
      subdomain = "mcp-gateway"
      backend   = "http://localhost:8040"
    }
  }

  # DNS and tunnel routing cover every reachable host; Cloudflare Access is
  # applied only to local.services (the Access-protected, directly-reached set).
  all_services = merge(local.services, local.public_services)

  # When using a tunnel, all records are CNAMEs pointing to the tunnel hostname.
  # When pointing directly at the VPS, all records are A records.
  use_tunnel = var.target_mode == "local-tunnel"
}

resource "cloudflare_record" "services" {
  for_each = local.all_services

  zone_id = var.cloudflare_zone_id
  name    = each.value.subdomain
  type    = local.use_tunnel ? "CNAME" : "A"
  content = local.use_tunnel ? "${cloudflare_zero_trust_tunnel_cloudflared.platform[0].id}.cfargotunnel.com" : var.vps_ipv4
  proxied = true

  lifecycle {
    precondition {
      condition     = local.use_tunnel || var.vps_ipv4 != null
      error_message = "vps_ipv4 is required when target_mode is vps-ip."
    }
  }
}

# ---------------------------------------------------------------------------
# Cloudflare Access
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_access_application" "services" {
  for_each = var.cloudflare_access_enabled ? local.services : {}

  account_id                   = var.cloudflare_account_id
  name                         = "personal-platform-${each.key}"
  domain                       = "${each.value.subdomain}.${var.domain}"
  type                         = "self_hosted"
  session_duration             = var.cloudflare_access_session_duration
  allowed_idps                 = var.cloudflare_access_allowed_idps
  auto_redirect_to_identity    = length(var.cloudflare_access_allowed_idps) == 1
  service_auth_401_redirect    = true
  http_only_cookie_attribute   = true
  same_site_cookie_attribute   = "lax"
  options_preflight_bypass     = true
  app_launcher_visible         = false
  skip_interstitial            = true
  allow_authenticate_via_warp  = false
  enable_binding_cookie        = true
  skip_app_launcher_login_page = false

  lifecycle {
    precondition {
      condition = (
        length(var.cloudflare_access_allowed_emails) > 0 ||
        length(var.cloudflare_access_allowed_email_domains) > 0 ||
        var.cloudflare_access_service_token_enabled
      )
      error_message = "Cloudflare Access requires at least one allowed email, allowed email domain, or enabled service token."
    }
  }
}

resource "cloudflare_zero_trust_access_policy" "human_allow" {
  for_each = (
    var.cloudflare_access_enabled &&
    (length(var.cloudflare_access_allowed_emails) > 0 || length(var.cloudflare_access_allowed_email_domains) > 0)
  ) ? local.services : {}

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.services[each.key].id
  name           = "allow-human-identities"
  decision       = "allow"
  precedence     = 1

  include {
    email        = var.cloudflare_access_allowed_emails
    email_domain = var.cloudflare_access_allowed_email_domains
  }
}

resource "cloudflare_zero_trust_access_service_token" "automation" {
  count = var.cloudflare_access_enabled && var.cloudflare_access_service_token_enabled ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = "personal-platform-automation"
  duration   = var.cloudflare_access_service_token_duration
}

resource "cloudflare_zero_trust_access_policy" "service_token_allow" {
  for_each = var.cloudflare_access_enabled && var.cloudflare_access_service_token_enabled ? local.services : {}

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.services[each.key].id
  name           = "allow-service-token"
  decision       = "allow"
  precedence     = 2

  include {
    service_token = [cloudflare_zero_trust_access_service_token.automation[0].id]
  }
}
