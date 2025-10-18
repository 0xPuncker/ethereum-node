variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
  nullable    = false
}

variable "name_prefix" {
  description = "Prefix for load balancer resources"
  type        = string
  nullable    = false
}

variable "instance_group" {
  description = "Instance group to backend to the load balancer"
  type        = string
  nullable    = false
}

variable "health_check_port" {
  description = "Port for health check"
  type        = number
  default     = 80
  nullable    = false
}

variable "backend_protocol" {
  description = "Protocol for backend service"
  type        = string
  default     = "HTTP"
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to load balancer resources"
  type        = map(string)
  default     = {}
}
