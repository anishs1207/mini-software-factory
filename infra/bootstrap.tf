# Local SSH bootstrap reads ignored API keys; Terraform state receives no key values.
locals {
  agent_source_hash = sha256(join("", [for source in sort(concat(
    tolist(fileset("${path.module}/../agents", "**/*.sh")),
    tolist(fileset("${path.module}/../agents", "**/*.py")),
    tolist(fileset("${path.module}/../agents", "**/*.md"))
  )) : filesha256("${path.module}/../agents/${source}")]))
}

resource "terraform_data" "bootstrap_preflight" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [var.aws_profile, local.agent_source_hash]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --preflight"
    environment = {
      FACTORY_SSH_PRIVATE_KEY = data.external.local_prereqs.result.ssh_private_key_path
      FACTORY_AWS_PROFILE     = var.aws_profile
    }
  }
}

resource "terraform_data" "bootstrap_agents" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [aws_instance.briefing.id, local.agent_source_hash]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --bootstrap"
    environment = {
      FACTORY_VM_IP           = aws_instance.briefing.public_ip
      FACTORY_SSH_PRIVATE_KEY = data.external.local_prereqs.result.ssh_private_key_path
      FACTORY_AWS_PROFILE     = var.aws_profile
      FACTORY_NO_AUTO_CHAT    = var.no_auto_chat ? "1" : "0"
    }
  }
}
