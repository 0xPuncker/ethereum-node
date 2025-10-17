terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }

  backend "gcs" {
    bucket = "eth-node-terraform-state"
    prefix = "eth-node/state"
  }
}
