# Get the Cloud Storage service account for KMS encryption
data "google_storage_project_service_account" "gcs_account" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "storage_kms_encrypter" {
  crypto_key_id = var.kms_key_self_link
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

resource "google_kms_crypto_key_iam_member" "storage_kms_viewer" {
  crypto_key_id = var.kms_key_self_link
  role          = "roles/cloudkms.viewer"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}


resource "google_storage_bucket" "this" {
  name                        = var.bucket_name
  location                    = var.location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  encryption {
    default_kms_key_name = var.kms_key_self_link
  }

  lifecycle {
    prevent_destroy = false
  }

  # Ensure KMS permissions are set before creating bucket
  depends_on = [
    google_kms_crypto_key_iam_member.storage_kms_encrypter,
    google_kms_crypto_key_iam_member.storage_kms_viewer
  ]
}

resource "google_storage_bucket_iam_member" "service_account_roles" {
  for_each = toset(var.bucket_roles)

  bucket = google_storage_bucket.this.name
  role   = each.value
  member = "serviceAccount:${var.service_account_email}"
}
