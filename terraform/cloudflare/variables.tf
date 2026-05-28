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
