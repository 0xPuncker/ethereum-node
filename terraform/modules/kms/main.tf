# Note: GCP KMS keyrings cannot be deleted, they persist indefinitely.
# Set `create_key_ring = false` (and optionally `create_crypto_key = false`) to adopt existing resources.
resource "google_kms_key_ring" "this" {
  count    = var.create_key_ring ? 1 : 0
  name     = var.key_ring_name
  location = var.region
  project  = var.project_id

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      name,
      location,
    ]
  }
}

data "google_kms_key_ring" "existing" {
  count    = var.create_key_ring ? 0 : 1
  name     = var.key_ring_name
  project  = var.project_id
  location = var.region
}

locals {
  key_ring_id = var.create_key_ring ? one(google_kms_key_ring.this).id : one(data.google_kms_key_ring.existing).id
}

resource "google_kms_crypto_key" "this" {
  count           = var.create_crypto_key ? 1 : 0
  name            = var.crypto_key_name
  key_ring        = local.key_ring_id
  rotation_period = var.rotation_period
  labels = merge(var.common_tags, {
    name = var.crypto_key_name
  })

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      rotation_period,
    ]
  }
}

data "google_kms_crypto_key" "existing" {
  count    = var.create_crypto_key ? 0 : 1
  name     = var.crypto_key_name
  key_ring = local.key_ring_id
}

locals {
  crypto_key_id = var.create_crypto_key ? one(google_kms_crypto_key.this).id : one(data.google_kms_crypto_key.existing).id
}
