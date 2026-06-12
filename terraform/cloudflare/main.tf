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
  # Access-protected services (default). Cloudflare Access application and
  # policies are created only for these entries.
  services = { for k, v in var.services : k => v if v.access_protected }

  # Public services (access_protected = false). These get DNS and tunnel
  # routing but are intentionally NOT placed behind Cloudflare Access —
  # e.g. the MCP gateway runs its own OAuth flow and an Access interstitial
  # would break third-party OAuth clients such as ChatGPT.
  public_services = { for k, v in var.services : k => v if !v.access_protected }

  # DNS and tunnel routing cover every reachable host.
  all_services = var.services

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

# ---------------------------------------------------------------------------
# Status page (Cloudflare Worker) — Access enforcement
#
# The Worker itself is deployed via wrangler (cloudflare/workers/status-page);
# its route DNS is managed by the Worker route. Access is enforced here so the
# page — which lists internal hostnames and live health state — is not public.
# ---------------------------------------------------------------------------

locals {
  status_page_protected = var.cloudflare_access_enabled && var.status_page_access_enabled
}

resource "cloudflare_zero_trust_access_application" "status_page" {
  count = local.status_page_protected ? 1 : 0

  account_id                   = var.cloudflare_account_id
  name                         = "personal-platform-status-page"
  domain                       = "${var.status_page_subdomain}.${var.domain}"
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

resource "cloudflare_zero_trust_access_policy" "status_page_human_allow" {
  count = (
    local.status_page_protected &&
    (length(var.cloudflare_access_allowed_emails) > 0 || length(var.cloudflare_access_allowed_email_domains) > 0)
  ) ? 1 : 0

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.status_page[0].id
  name           = "allow-human-identities"
  decision       = "allow"
  precedence     = 1

  include {
    email        = var.cloudflare_access_allowed_emails
    email_domain = var.cloudflare_access_allowed_email_domains
  }
}

resource "cloudflare_zero_trust_access_policy" "status_page_service_token_allow" {
  count = local.status_page_protected && var.cloudflare_access_service_token_enabled ? 1 : 0

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.status_page[0].id
  name           = "allow-service-token"
  decision       = "allow"
  precedence     = 2

  include {
    service_token = [cloudflare_zero_trust_access_service_token.automation[0].id]
  }
}
