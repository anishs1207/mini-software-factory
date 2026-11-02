variable "oci_profile" { type = string, default = "DEFAULT" }
variable "region" { type = string }
variable "compartment_id" { type = string }
variable "availability_domain" { type = string }
variable "subnet_id" {
  type        = string
  default     = null
  description = "Optional existing public subnet OCID; when omitted Terraform creates a VCN and public subnet."
}
variable "ssh_allowed_cidr" {
  type        = string
  default     = null
  description = "Your public IPv4 address as a /32 CIDR for SSH when Terraform creates the subnet."
  validation {
    condition     = var.ssh_allowed_cidr == null || can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR such as 203.0.113.4/32."
  }
}
variable "ssh_public_key_path" { type = string }
variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519"
  description = "Private key used by local bootstrap to reach the VM; key contents never enter Terraform state."
}
variable "bootstrap_agents" {
  type        = bool
  default     = true
  description = "Install and start the agent factory during terraform apply."
}
variable "bootstrap_python" {
  type        = string
  default     = "python"
  description = "Python 3 command on the Terraform machine; use python3 where needed."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.bootstrap_python))
    error_message = "Use a simple executable name such as python or python3."
  }
}
variable "ocpus" {
  type    = number
  default = 2
  validation { condition = var.ocpus >= 1 && var.ocpus <= 2, error_message = "Keep A1 at 1-2 OCPUs." }
}
variable "memory_gb" {
  type    = number
  default = 12
  validation { condition = var.memory_gb >= 6 && var.memory_gb <= 12, error_message = "Keep A1 at 6-12 GB." }
}
variable "image_id" {
  type        = string
  default     = null
  description = "Optional Ubuntu 24.04 aarch64 image OCID if automatic discovery fails."
}
