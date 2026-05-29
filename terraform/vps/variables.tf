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

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed to reach SSH and the k3s API."
  type        = list(string)
}

variable "labels" {
  description = "Additional labels to attach to the server."
  type        = map(string)
  default     = {}
}
