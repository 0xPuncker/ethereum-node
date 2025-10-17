output "crypto_key_id" {
  description = "ID of the crypto key"
  value       = google_kms_crypto_key.this.id
}

output "crypto_key_self_link" {
  description = "ID of the crypto key for encryption configuration"
  value       = google_kms_crypto_key.this.id
}

output "key_ring_id" {
  description = "ID of the key ring"
  value       = google_kms_key_ring.this.id
}
