resource "google_compute_network" "briefing" {
  name                    = "briefing-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "briefing" {
  name          = "briefing-public-subnet"
  region        = var.region
  network       = google_compute_network.briefing.id
  ip_cidr_range = "10.77.1.0/24"
}

resource "google_compute_firewall" "ssh" {
  name          = "briefing-ssh"
  network       = google_compute_network.briefing.name
  target_tags   = ["briefing-agent"]
  source_ranges = [data.external.local_prereqs.result.ssh_allowed_cidr]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "product" {
  name          = "briefing-product"
  network       = google_compute_network.briefing.name
  target_tags   = ["briefing-agent"]
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "3000"]
  }
}
