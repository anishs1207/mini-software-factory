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
  triggers_replace = [var.project_id, local.agent_source_hash]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --preflight"
    environment = {
      FACTORY_SSH_PRIVATE_KEY = data.external.local_prereqs.result.ssh_private_key_path
      FACTORY_GCP_PROJECT     = var.project_id
    }
  }
}

resource "terraform_data" "bootstrap_agents" {
  count            = var.bootstrap_agents ? 1 : 0
  triggers_replace = [google_compute_instance.briefing.id, local.agent_source_hash]

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "${var.bootstrap_python} agents/setup/bootstrap-vm.py --bootstrap"
    environment = {
      FACTORY_VM_IP           = google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip
      FACTORY_SSH_PRIVATE_KEY = data.external.local_prereqs.result.ssh_private_key_path
      FACTORY_GCP_PROJECT     = var.project_id
      FACTORY_NO_AUTO_CHAT    = var.no_auto_chat ? "1" : "0"
      FACTORY_RESUME_ISSUE    = "1"
    }
  }
}
