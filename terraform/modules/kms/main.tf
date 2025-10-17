# Note: GCP KMS keyrings cannot be deleted, they persist indefinitely
# If you get "KeyRing already exists" error, import the existing resource:
#   terraform import module.kms.google_kms_key_ring.this projects/PROJECT_ID/locations/REGION/keyRings/KEYRING_NAME
resource "google_kms_key_ring" "this" {
  name     = var.key_ring_name
  location = var.region
  project  = var.project_id

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      name,
      location,
    ]
  }
}

resource "google_kms_crypto_key" "this" {
  name            = var.crypto_key_name
  key_ring        = google_kms_key_ring.this.id
  rotation_period = var.rotation_period
  labels = merge(var.common_tags, {
    name = var.crypto_key_name
  })

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      rotation_period,
    ]
  }
}
