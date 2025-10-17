output "service_account_email" {
  description = "Email of the service account used by the instance"
  value       = google_service_account.this.email
}

output "instance_self_link" {
  description = "Self link of the Compute Engine instance"
  value       = google_compute_instance.vm.self_link
}

output "instance_id" {
  description = "ID of the Compute Engine instance"
  value       = google_compute_instance.vm.id
}

output "data_disk_self_link" {
  description = "Self link of the attached data disk"
  value       = google_compute_disk.data.self_link
}

output "instance_group_id" {
  description = "ID of the instance group"
  value       = google_compute_instance_group.this.id
}

output "instance_external_ip" {
  description = "External IP address of the Compute Engine instance"
  value       = google_compute_address.static.address
}

output "static_ip_address" {
  description = "Reserved static external IP address"
  value       = google_compute_address.static.address
}
