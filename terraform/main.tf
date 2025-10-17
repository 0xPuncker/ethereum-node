locals {
  region          = var.region
  prefix          = var.resource_prefix
  ssh_public_cidr = ["${trimspace(data.http.my_public_ip.response_body)}/32"]
}

data "http" "my_public_ip" {

  url = "https://api.ipify.org"
}

module "kms" {
  source          = "./modules/kms"
  project_id      = var.project_id
  region          = local.region
  crypto_key_name = local.prefix
  rotation_period = var.kms_rotation_period
  key_ring_name   = "${local.prefix}-val-keyring"
}

module "network" {
  source            = "./modules/network"
  project_id        = var.project_id
  region            = local.region
  network_name      = "${local.prefix}-vpc"
  subnet_name       = "${local.prefix}-subnet"
  subnet_cidr       = var.subnet_cidr
  source_ranges     = var.firewall_source_ranges
  allowed_ports     = var.firewall_allowed_ports
  ssh_source_ranges = local.ssh_public_cidr
}

module "compute" {
  source              = "./modules/compute"
  project_id          = var.project_id
  region              = local.region
  zone                = var.zone
  instance_name       = "${local.prefix}-vm"
  machine_type        = var.machine_type
  boot_disk           = var.boot_disk
  data_disk           = var.data_disk
  subnet_self_link    = module.network.subnet_self_link
  network_tags        = [module.network.network_tag]
  kms_key_self_link   = module.kms.crypto_key_self_link
  service_account_id  = "${local.prefix}-sa"
  ssh_user            = var.ansible_user
  ssh_public_key_file = var.ssh_public_key_file
}

module "storage" {
  source                = "./modules/storage"
  project_id            = var.project_id
  bucket_name           = "${local.prefix}-bucket"
  bucket_roles          = var.bucket_roles
  service_account_email = module.compute.service_account_email
  location              = local.region
  kms_key_self_link     = module.kms.crypto_key_self_link
}

module "loadbalancer" {
  source         = "./modules/loadbalancer"
  project_id     = var.project_id
  name_prefix    = "${local.prefix}-lb"
  instance_group = module.compute.instance_group_id
}
