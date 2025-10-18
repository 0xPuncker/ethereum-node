locals {
  network_tag = "${var.network_name}-network"

}

resource "google_compute_network" "this" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  project       = var.project_id
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "ingress" {
  name    = "${var.network_name}-ingress"
  project = var.project_id
  network = google_compute_network.this.name

  direction = "INGRESS"
  priority  = 1000

  target_tags = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = var.allowed_ports
  }

  source_ranges = var.source_ranges
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.network_name}-ssh"
  project = var.project_id
  network = google_compute_network.this.name

  direction = "INGRESS"
  priority  = 900

  target_tags = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
}
