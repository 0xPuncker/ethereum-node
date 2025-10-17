output "crypto_key_id" {
  description = "ID of the crypto key"
  value       = local.crypto_key_id
}

output "crypto_key_self_link" {
  description = "ID of the crypto key for encryption configuration"
  value       = local.crypto_key_id
}

output "key_ring_id" {
  description = "ID of the key ring"
  value       = local.key_ring_id
}
