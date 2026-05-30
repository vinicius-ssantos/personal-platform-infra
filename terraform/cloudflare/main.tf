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
# Cloudflare Tunnel
# ---------------------------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared" "platform" {
  account_id = var.cloudflare_account_id
  name       = "personal-platform"
  secret     = var.tunnel_secret
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "platform" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.platform.id

  config {
    dynamic "ingress_rule" {
      for_each = local.services
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

  # When using a tunnel, all records are CNAMEs pointing to the tunnel hostname.
  # When pointing directly at the VPS, all records are A records.
  use_tunnel = var.target_mode == "local-tunnel"
}

resource "cloudflare_record" "services" {
  for_each = local.services

  zone_id = var.cloudflare_zone_id
  name    = each.value.subdomain
  type    = local.use_tunnel ? "CNAME" : "A"
  content = local.use_tunnel ? "${cloudflare_zero_trust_tunnel_cloudflared.platform.id}.cfargotunnel.com" : var.vps_ipv4
  proxied = true
}
