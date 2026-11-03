variable "aws_profile" {
  type        = string
  default     = "default"
  description = "Local AWS shared-config profile used by the Terraform AWS provider."
}
variable "region" {
  type        = string
  default     = null
  description = "AWS region; null uses the selected AWS CLI profile's region."
}
variable "ssh_allowed_cidr" {
  type        = string
  default     = null
  description = "Operator public IPv4 address as a /32 CIDR for SSH."
  validation {
    condition     = var.ssh_allowed_cidr == null || (can(cidrhost(var.ssh_allowed_cidr, 0)) && endswith(var.ssh_allowed_cidr, "/32"))
    error_message = "Set ssh_allowed_cidr to your public IPv4 /32, such as 203.0.113.4/32."
  }
}
variable "ssh_public_key_path" {
  type        = string
  default     = null
  description = "Optional existing SSH public key; otherwise plan generates an ignored local key pair."
}
variable "ssh_private_key_path" {
  type        = string
  default     = null
  description = "Local private key used by SSH bootstrap; its contents never enter Terraform state."
}
variable "bootstrap_agents" {
  type        = bool
  default     = true
  description = "Install and start the agent factory during terraform apply."
}
variable "no_auto_chat" {
  type        = bool
  default     = false
  description = "Skip the new SSH console when another wrapper will open the manager chat."
}
variable "bootstrap_python" {
  type        = string
  default     = "python"
  description = "Python 3 command on the Terraform machine."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.bootstrap_python))
    error_message = "Use a simple executable name such as python or python3."
  }
}
variable "ami_id" {
  type        = string
  default     = null
  description = "Optional Ubuntu 24.04 amd64 AMI override; otherwise use Canonical's public SSM parameter."
}
