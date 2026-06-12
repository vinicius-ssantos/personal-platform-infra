variable "cloudflare_api_token" {
  description = "Cloudflare API token. Prefer TF_VAR_cloudflare_api_token or a secrets manager."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the main domain."
  type        = string
}

variable "domain" {
  description = "Base domain, for example example.com."
  type        = string
}

variable "target_mode" {
  description = "Target mode for DNS: local-tunnel or vps-ip."
  type        = string
  default     = "local-tunnel"

  validation {
    condition     = contains(["local-tunnel", "vps-ip"], var.target_mode)
    error_message = "target_mode must be local-tunnel or vps-ip."
  }
}

variable "vps_ipv4" {
  description = "VPS IPv4 address when target_mode is vps-ip."
  type        = string
  default     = null
}

variable "tunnel_secret" {
  description = "32-byte base64-encoded secret for the Cloudflare Tunnel. Required when target_mode is local-tunnel. Generate with: openssl rand -hex 32 | base64"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_access_enabled" {
  description = "Whether Terraform should manage Cloudflare Access applications and policies for public service hostnames."
  type        = bool
  default     = false
}

variable "cloudflare_access_allowed_emails" {
  description = "Human user email addresses allowed through Cloudflare Access."
  type        = list(string)
  default     = []
}

variable "cloudflare_access_allowed_email_domains" {
  description = "Human email domains allowed through Cloudflare Access."
  type        = list(string)
  default     = []
}

variable "cloudflare_access_allowed_idps" {
  description = "Optional Cloudflare Access identity provider IDs allowed for these applications."
  type        = list(string)
  default     = []
}

variable "cloudflare_access_service_token_enabled" {
  description = "Whether to create an Access service token and allow it through each application for automation."
  type        = bool
  default     = false
}

variable "cloudflare_access_service_token_duration" {
  description = "Lifetime for the optional Access service token."
  type        = string
  default     = "8760h"
}

variable "cloudflare_access_session_duration" {
  description = "How long a human Access login session is valid."
  type        = string
  default     = "8h"
}

variable "status_page_subdomain" {
  description = "Subdomain where the status page Worker is routed (see cloudflare/workers/status-page)."
  type        = string
  default     = "status"
}

variable "status_page_access_enabled" {
  description = "Whether to enforce Cloudflare Access on the status page hostname. Requires cloudflare_access_enabled = true. The page exposes internal hostnames and health state, so keep it protected unless intentionally public."
  type        = bool
  default     = true
}

variable "services" {
  description = "Services to expose via DNS, Cloudflare Tunnel, and (optionally) Access. Set access_protected = false for public OAuth endpoints that must not sit behind an Access login interstitial."
  type = map(object({
    subdomain        = string
    backend          = string
    access_protected = optional(bool, true)
  }))
  default = {
    mcp_github = {
      subdomain = "mcp-github"
      backend   = "http://localhost:8765"
    }
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
    mcp_gateway = {
      subdomain        = "mcp-gateway"
      backend          = "http://localhost:8040"
      access_protected = false
    }
  }
}
