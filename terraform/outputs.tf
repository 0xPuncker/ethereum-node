output "vm_self_link" {
  description = "Self link of the Compute Engine VM"
  value       = module.compute.instance_self_link
}

output "service_account_email" {
  description = "Email of the service account assigned to the VM"
  value       = module.compute.service_account_email
}

output "bucket_name" {
  description = "Name of the application bucket"
  value       = module.storage.bucket_name
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = module.network.network_self_link
}

output "subnet_self_link" {
  description = "Self link of the subnet"
  value       = module.network.subnet_self_link
}

output "kms_crypto_key_id" {
  description = "ID of the CMEK key used for encryption"
  value       = module.kms.crypto_key_id
}

output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = module.loadbalancer.load_balancer_ip
}

output "load_balancer_url" {
  description = "URL to access the load balancer"
  value       = "http://${module.loadbalancer.load_balancer_ip}"
}

output "vm_external_ip" {
  description = "External IP address of the VM for SSH access"
  value       = module.compute.instance_external_ip
}

output "vm_static_ip" {
  description = "Reserved static IP address for the VM"
  value       = module.compute.static_ip_address
}

output "ansible_user" {
  description = "SSH user for Ansible connections"
  value       = var.ansible_user
}
