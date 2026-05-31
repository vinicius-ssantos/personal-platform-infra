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

output "cloudflare_access_applications" {
  description = "Cloudflare Access application IDs and hostnames when Access is enabled."
  value = {
    for key, app in cloudflare_zero_trust_access_application.services :
    key => {
      id     = app.id
      domain = app.domain
      aud    = app.aud
    }
  }
}

output "cloudflare_access_service_token_client_id" {
  description = "Access service token client ID for automation when service token support is enabled."
  value       = try(cloudflare_zero_trust_access_service_token.automation[0].client_id, null)
  sensitive   = true
}

output "cloudflare_access_service_token_client_secret" {
  description = "Access service token client secret for automation. Store it in a secret manager immediately after creation."
  value       = try(cloudflare_zero_trust_access_service_token.automation[0].client_secret, null)
  sensitive   = true
}
