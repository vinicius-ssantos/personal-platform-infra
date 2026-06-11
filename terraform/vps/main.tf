terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "operator" {
  name       = var.ssh_key_name
  public_key = var.ssh_public_key
}

locals {
  # When using a Cloudflare Tunnel the VPS initiates the connection outbound;
  # no inbound HTTP/HTTPS rule is needed. When using the DNS-proxy mode
  # (vps-ip) Cloudflare's edge servers connect to the VPS, so we restrict to
  # their published ranges instead of opening 0.0.0.0/0.
  http_source_ips = var.use_cloudflare_tunnel ? [] : concat(
    var.cloudflare_ipv4_ranges,
    var.cloudflare_ipv6_ranges,
  )
}

resource "hcloud_firewall" "platform" {
  name = "${var.server_name}-firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidr_blocks
  }

  dynamic "rule" {
    for_each = var.use_cloudflare_tunnel ? [] : [80]
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(rule.value)
      source_ips = local.http_source_ips
    }
  }

  dynamic "rule" {
    for_each = var.use_cloudflare_tunnel ? [] : [443]
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = tostring(rule.value)
      source_ips = local.http_source_ips
    }
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.admin_cidr_blocks
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "platform" {
  name        = var.server_name
  image       = var.server_image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.operator.id]
  firewall_ids = [
    hcloud_firewall.platform.id,
  ]

  labels = merge(
    {
      app     = "personal-platform"
      managed = "terraform"
    },
    var.labels,
  )

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}
