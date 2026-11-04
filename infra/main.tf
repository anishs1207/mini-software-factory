data "external" "local_prereqs" {
  program = [var.bootstrap_python, abspath("${path.module}/../agents/setup/local-prereqs.py")]
  query = {
    workspace_root       = abspath("${path.module}/..")
    ssh_public_key_path  = var.ssh_public_key_path == null ? "" : var.ssh_public_key_path
    ssh_private_key_path = var.ssh_private_key_path == null ? "" : var.ssh_private_key_path
    ssh_allowed_cidr     = var.ssh_allowed_cidr == null ? "" : var.ssh_allowed_cidr
  }
}

resource "google_compute_instance" "briefing" {
  depends_on   = [terraform_data.bootstrap_preflight, google_compute_firewall.ssh, google_compute_firewall.product]
  name         = "briefing-agent-vm"
  machine_type = "n4-standard-2"
  zone         = var.zone
  tags         = ["briefing-agent"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "hyperdisk-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.briefing.id
    access_config {}
  }

  metadata = {
    ssh-keys = "ubuntu:${data.external.local_prereqs.result.public_key}"
  }
}
