variable "project_id" {
  description = "Project ID where the bucket is created"
  type        = string
}

variable "location" {
  description = "Location for the bucket"
  type        = string
}

variable "bucket_name" {
  description = "Name of the bucket"
  type        = string
}

variable "kms_key_self_link" {
  description = "Self link of the KMS key used for bucket encryption"
  type        = string
}

variable "service_account_email" {
  description = "Service account email granted access to the bucket"
  type        = string
}

variable "bucket_roles" {
  description = "List of IAM roles granted to the service account on the bucket"
  type        = list(string)
}
