resource "google_compute_address" "static" {
  name         = "${var.instance_name}-ip"
  address_type = "EXTERNAL"
  region       = var.region
  project      = var.project_id
  labels = merge(var.common_tags, {
    name = "${var.instance_name}-ip"
  })
}

resource "google_service_account" "this" {
  account_id   = var.service_account_id
  display_name = "Service Account for ${var.instance_name}"
  project      = var.project_id
}

resource "google_kms_crypto_key_iam_member" "compute_sa" {
  crypto_key_id = var.kms_key_self_link
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.this.email}"
}

resource "google_compute_disk" "data" {
  name    = "${var.instance_name}-data"
  type    = var.data_disk.type
  size    = var.data_disk.size
  zone    = var.zone
  project = var.project_id
  labels = merge(var.common_tags, {
    name = "${var.instance_name}-data"
  })

  disk_encryption_key {
    kms_key_self_link = var.kms_key_self_link
  }

  depends_on = [google_kms_crypto_key_iam_member.compute_sa]
}

resource "google_compute_instance" "vm" {
  name                      = var.instance_name
  machine_type              = var.machine_type
  zone                      = var.zone
  project                   = var.project_id
  tags                      = var.network_tags
  allow_stopping_for_update = true
  labels = merge(var.common_tags, {
    name = var.instance_name
  })

  boot_disk {
    initialize_params {
      image = var.boot_disk.image
      type  = var.boot_disk.type
      size  = var.boot_disk.size
    }
  }

  attached_disk {
    source = google_compute_disk.data.id
  }

  network_interface {
    subnetwork = var.subnet_self_link
    access_config {
      nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_file)}"
  }

  service_account {
    email  = google_service_account.this.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [google_kms_crypto_key_iam_member.compute_sa]
}

resource "google_compute_instance_group" "this" {
  name    = "${var.instance_name}-group"
  zone    = var.zone
  project = var.project_id

  instances = [google_compute_instance.vm.self_link]

  named_port {
    name = "http"
    port = var.backend_port
  }
}
