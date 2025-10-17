variable "project_id" {
  description = "Project ID for the compute resources"
  type        = string
}

variable "region" {
  description = "Region for the compute resources"
  type        = string
}

variable "zone" {
  description = "Zone for the compute resources"
  type        = string
}

variable "instance_name" {
  description = "Name of the Compute Engine instance"
  type        = string
}

variable "machine_type" {
  description = "Machine type for the instance"
  type        = string
}

variable "boot_disk" {
  description = "Boot disk configuration"
  type = object({
    image = string
    type  = string
    size  = number
  })
}

variable "data_disk" {
  description = "Data disk configuration"
  type = object({
    type = string
    size = number
  })
}

variable "subnet_self_link" {
  description = "Self link of the subnet to attach the instance to"
  type        = string
}

variable "network_tags" {
  description = "Network tags to apply to the instance"
  type        = list(string)
}

variable "kms_key_self_link" {
  description = "Self link of the KMS key used for disk encryption"
  type        = string
}

variable "service_account_id" {
  description = "Account ID (name) for the service account without domain suffix"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for the instance"
  type        = string
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "backend_port" {
  description = "Port for backend service"
  type        = number
  default     = 3000
  nullable    = false
}
