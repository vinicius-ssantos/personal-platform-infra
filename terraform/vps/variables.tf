variable "hcloud_token" {
  description = "Hetzner Cloud API token. Prefer TF_VAR_hcloud_token or a secrets manager."
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "VPS server name."
  type        = string
  default     = "personal-platform"
}

variable "server_type" {
  description = "Hetzner server type."
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Server image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "location" {
  description = "Hetzner location."
  type        = string
  default     = "fsn1"
}

variable "ssh_key_name" {
  description = "Name to register for the operator SSH key."
  type        = string
  default     = "personal-platform-operator"
}

variable "ssh_public_key" {
  description = "Public SSH key allowed to access the VPS."
  type        = string
}

variable "labels" {
  description = "Additional labels to attach to the server."
  type        = map(string)
  default     = {}
}

variable "use_cloudflare_tunnel" {
  description = <<-EOT
    Set to true when traffic reaches the VPS via a Cloudflare Tunnel (cloudflared
    outbound connection). In that mode ports 80/443 need not be open inbound and
    the corresponding firewall rules are omitted entirely.

    Set to false (default) when target_mode = "vps-ip" in the Cloudflare workspace:
    Cloudflare acts as a reverse proxy and connects to the VPS from its published
    IP ranges, so those ranges are used instead of 0.0.0.0/0.
  EOT
  type        = bool
  default     = false
}

# Cloudflare published egress ranges — https://www.cloudflare.com/ips/
# Used only when use_cloudflare_tunnel = false.
variable "cloudflare_ipv4_ranges" {
  description = "Cloudflare IPv4 proxy ranges (source IPs for ports 80/443)."
  type        = list(string)
  default = [
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "108.162.192.0/18",
    "131.0.72.0/22",
    "141.101.64.0/18",
    "162.158.0.0/15",
    "172.64.0.0/13",
    "173.245.48.0/20",
    "188.114.96.0/20",
    "190.93.240.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
  ]
}

variable "cloudflare_ipv6_ranges" {
  description = "Cloudflare IPv6 proxy ranges (source IPs for ports 80/443)."
  type        = list(string)
  default = [
    "2400:cb00::/32",
    "2405:8100::/32",
    "2405:b500::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed to reach SSH and the k3s API."
  type        = list(string)

  validation {
    condition = !contains([
      for cidr in var.admin_cidr_blocks :
      cidr
      if cidr == "0.0.0.0/0" || cidr == "::/0"
      ], "0.0.0.0/0") && !contains([
      for cidr in var.admin_cidr_blocks :
      cidr
      if cidr == "0.0.0.0/0" || cidr == "::/0"
    ], "::/0")
    error_message = "admin_cidr_blocks must not contain 0.0.0.0/0 or ::/0 — that would expose SSH and the k3s API to the entire internet."
  }
}
