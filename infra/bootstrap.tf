# Local SSH bootstrap reads ignored API keys; Terraform state receives no key values.
resource "terraform_data" "bootstrap_preflight" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [var.aws_profile, var.spec_path, filesha256("${path.module}/../${var.spec_path}")]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --preflight"
    environment = {
      BRIEFING_SSH_PRIVATE_KEY = pathexpand(var.ssh_private_key_path)
      BRIEFING_SPEC_PATH       = var.spec_path
      BRIEFING_AWS_PROFILE     = var.aws_profile
    }
  }
}

resource "terraform_data" "bootstrap_agents" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [aws_instance.briefing.id, var.spec_path, filesha256("${path.module}/../${var.spec_path}")]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --bootstrap"
    environment = {
      BRIEFING_VM_IP           = aws_instance.briefing.public_ip
      BRIEFING_SSH_PRIVATE_KEY = pathexpand(var.ssh_private_key_path)
      BRIEFING_SPEC_PATH       = var.spec_path
      BRIEFING_SPEC_HASH       = filesha256("${path.module}/../${var.spec_path}")
      BRIEFING_AWS_PROFILE     = var.aws_profile
    }
  }
}
