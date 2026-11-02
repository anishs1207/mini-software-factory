# The Terraform machine runs bootstrap over SSH. API keys are read from a local
# ignored file and never passed through Terraform variables, metadata, or state.
resource "terraform_data" "bootstrap_preflight" {
  count = var.bootstrap_agents ? 1 : 0

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --preflight"
    environment = {
      BRIEFING_SSH_PRIVATE_KEY = pathexpand(var.ssh_private_key_path)
    }
  }
}

resource "terraform_data" "bootstrap_agents" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [oci_core_instance.briefing.id]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --bootstrap"
    environment = {
      BRIEFING_VM_IP           = data.oci_core_vnic.briefing.public_ip_address
      BRIEFING_SSH_PRIVATE_KEY = pathexpand(var.ssh_private_key_path)
    }
  }
}
