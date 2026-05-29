output "server_id" {
  description = "Hetzner server ID."
  value       = hcloud_server.platform.id
}

output "server_name" {
  description = "VPS server name."
  value       = hcloud_server.platform.name
}

output "ipv4_address" {
  description = "Public IPv4 address for DNS and Ansible inventory."
  value       = hcloud_server.platform.ipv4_address
}

output "ipv6_address" {
  description = "Public IPv6 address."
  value       = hcloud_server.platform.ipv6_address
}
