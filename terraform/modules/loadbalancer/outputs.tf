output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = google_compute_global_address.this.address
}

output "load_balancer_ip_name" {
  description = "Name of the load balancer IP address resource"
  value       = google_compute_global_address.this.name
}

output "backend_service_id" {
  description = "ID of the backend service"
  value       = google_compute_backend_service.this.id
}

output "url_map_id" {
  description = "ID of the URL map"
  value       = google_compute_url_map.this.id
}

output "health_check_id" {
  description = "ID of the health check"
  value       = google_compute_health_check.this.id
}
