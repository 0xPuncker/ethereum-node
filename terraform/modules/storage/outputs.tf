output "bucket_name" {
  description = "Name of the storage bucket"
  value       = google_storage_bucket.this.name
}

output "bucket_self_link" {
  description = "Self link of the storage bucket"
  value       = google_storage_bucket.this.self_link
}
