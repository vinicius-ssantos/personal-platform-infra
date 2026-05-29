output "domain" {
  value = var.domain
}

output "target_mode" {
  value = var.target_mode
}

output "tunnel_id" {
  description = "Cloudflare Tunnel ID — used to build CNAME targets."
  value       = cloudflare_zero_trust_tunnel_cloudflared.platform.id
}

output "tunnel_cname" {
  description = "CNAME value that DNS records point to when using tunnel mode."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.platform.id}.cfargotunnel.com"
}

output "service_hostnames" {
  description = "Public hostnames for each service."
  value = {
    for k, v in local.services :
    k => "${v.subdomain}.${var.domain}"
  }
}
