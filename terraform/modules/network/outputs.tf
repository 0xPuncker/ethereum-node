output "network_self_link" {
  description = "Self link of the VPC network"
  value       = google_compute_network.this.self_link
}

output "network_tag" {
  description = "Network tag applied to instances for firewall targeting"
  value       = local.network_tag
}

output "subnet_self_link" {
  description = "Self link of the subnetwork"
  value       = google_compute_subnetwork.this.self_link
}
