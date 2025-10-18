variable "project_id" {
  description = "Project ID where the network resources are created"
  type        = string
}

variable "region" {
  description = "Region for the subnetwork"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnetwork"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the subnetwork"
  type        = string
}

variable "source_ranges" {
  description = "List of source ranges allowed by the firewall rule"
  type        = list(string)
}

variable "allowed_ports" {
  description = "List of TCP ports allowed by the firewall rule"
  type        = list(string)
}

variable "ssh_source_ranges" {
  description = "List of source CIDR ranges allowed for SSH access (port 22)"
  type        = list(string)
  nullable    = false
}
