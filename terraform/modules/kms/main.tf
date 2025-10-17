resource "google_kms_key_ring" "this" {
  name     = var.key_ring_name
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "this" {
  name            = var.crypto_key_name
  key_ring        = google_kms_key_ring.this.id
  rotation_period = var.rotation_period

  lifecycle {
    prevent_destroy = false
  }
}
