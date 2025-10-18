variable "project_id" {
  description = "Project ID where the KMS resources are created"
  type        = string
}

variable "region" {
  description = "Region for the KMS key ring"
  type        = string
}

variable "key_ring_name" {
  description = "Name of the key ring"
  type        = string
}

variable "crypto_key_name" {
  description = "Name of the crypto key"
  type        = string
}

variable "rotation_period" {
  description = "Rotation period for the crypto key"
  type        = string
}

variable "create_key_ring" {
  description = "Whether to create the key ring (set to false to use an existing key ring)"
  type        = bool
  default     = true
}

variable "create_crypto_key" {
  description = "Whether to create the crypto key (set to false to use an existing crypto key)"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to KMS resources"
  type        = map(string)
  default     = {}
}
