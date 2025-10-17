variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
  nullable    = false
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  nullable    = false
}

variable "resource_prefix" {
  description = "Prefix used when naming resources"
  type        = string
  default     = "eth-node"
  nullable    = false
}

variable "machine_type" {
  description = "Compute Engine machine type"
  type        = string
}

variable "boot_disk" {
  description = "Boot disk configuration"
  type = object({
    image = string
    type  = string
    size  = number
  })
  default = {
    image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    type  = "pd-balanced"
    size  = 50
  }
}

variable "data_disk" {
  description = "Attached data disk configuration"
  type = object({
    type = string
    size = number
  })
  default = {
    type = "pd-balanced"
    size = 200
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the custom subnetwork"
  type        = string
  default     = "10.20.0.0/24"
}

variable "firewall_source_ranges" {
  description = "Allowed source CIDR ranges for ingress rules"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "firewall_allowed_ports" {
  description = "TCP ports allowed through the ingress firewall"
  type        = list(string)
  default     = ["22"]
}

variable "bucket_roles" {
  description = "Bucket IAM roles granted to the compute service account"
  type        = list(string)
  default = [
    "roles/storage.objectAdmin",
    "roles/storage.objectViewer",
    "roles/storage.admin",
    "roles/storage.legacyBucketOwner"
  ]
}

variable "kms_rotation_period" {
  description = "Rotation period for the CMEK key"
  type        = string
  default     = "2592000s"
}

variable "ansible_user" {
  description = "SSH user for Ansible connections"
  type        = string
  default     = "raulneiva"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
