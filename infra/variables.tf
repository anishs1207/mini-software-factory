variable "oci_profile" { type = string, default = "DEFAULT" }
variable "region" { type = string }
variable "compartment_id" { type = string }
variable "availability_domain" { type = string }
variable "subnet_id" { type = string }
variable "ssh_public_key_path" { type = string }
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
