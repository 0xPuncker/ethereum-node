# Terraform Infrastructure

GCP infrastructure provisioning for Ethereum validator deployment using OpenTofu/Terraform.

## Structure

```
terraform/
├── main.tf                  # Root module - orchestrates all modules
├── variables.tf             # Input variables
├── outputs.tf               # Output values for Ansible
├── provider.tf              # GCP provider configuration
├── versions.tf              # Terraform version constraints
├── terraform.tfvars         # Variable values (gitignored)
├── terraform.tfvars.example # Example configuration
└── modules/
    ├── compute/             # VM instance, service account, disks
    ├── network/             # VPC, subnet, firewall rules
    ├── kms/                 # Cloud KMS keyring and crypto key
    ├── storage/             # GCS bucket for encrypted keys
    └── loadbalancer/        # (Optional) Load balancer
```

## Quick Start

### Prerequisites

```bash
# Install OpenTofu (Terraform alternative)
brew install opentofu

# Or use Terraform
brew install terraform

# Authenticate with GCP
gcloud auth application-default login

# Set project
gcloud config set project YOUR_PROJECT_ID
```

### Deploy Infrastructure

```bash
# Initialize Terraform
tofu init

# Review planned changes
tofu plan

# Apply infrastructure
tofu apply -auto-approve

# Get outputs
tofu output
```

## Modules

### compute

VM instance with persistent disks, service account, and SSH configuration.

**Resources:**

- `google_compute_instance` - n2-standard-8 VM (8 vCPU, 32GB RAM)
- `google_compute_disk` - 1TB persistent SSD for blockchain data
- `google_compute_attached_disk` - Attach data disk to VM
- `google_service_account` - Service account with minimal permissions
- `google_project_iam_member` - IAM bindings for KMS decrypt

**Key Features:**

- Ubuntu 24.04 LTS boot disk
- Persistent SSD data disk (/dev/sdb)
- Static external IP
- Metadata for SSH keys
- Service account with KMS decrypt access

**Variables:**

```hcl
variable "machine_type" {
  default = "n2-standard-8"  # 8 vCPU, 32GB RAM
}

variable "boot_disk" {
  default = {
    size  = 50    # GB
    type  = "pd-balanced"
    image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  }
}

variable "data_disk" {
  default = {
    size = 500   # GB
    type = "pd-ssd"
  }
}
```

**Outputs:**

- `instance_id` - VM instance ID
- `external_ip` - Static external IP for SSH
- `internal_ip` - Internal VPC IP
- `service_account_email` - Service account email
- `instance_group_id` - Instance group (for load balancer)

### network

VPC network, subnet, and firewall rules.

**Resources:**

- `google_compute_network` - VPC network (auto-create subnets disabled)
- `google_compute_subnetwork` - Regional subnet
- `google_compute_firewall` (multiple) - Firewall rules for SSH, P2P

**Firewall Rules:**

```hcl
# SSH access (restricted to your IP)
allow-ssh: TCP/22 from your public IP

# Execution layer P2P
allow-execution-p2p: TCP+UDP/30303 from 0.0.0.0/0

# Consensus layer P2P
allow-consensus-p2p: TCP+UDP/9000 from 0.0.0.0/0
```

**Variables:**

```hcl
variable "network_name" {
  default = "eth-validator-vpc"
}

variable "subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "firewall_allowed_ports" {
  default = ["22", "30303", "9000"]
}
```

**Outputs:**

- `network_self_link` - VPC network self link
- `subnet_self_link` - Subnet self link
- `network_tag` - Network tag for firewall rules

### kms

Cloud KMS keyring and crypto key for validator key encryption.

**Resources:**

- `google_kms_key_ring` - KMS keyring (regional)
- `google_kms_crypto_key` - AES-256 encryption key
- `google_kms_crypto_key_iam_member` - IAM binding for service account

**Key Features:**

- AES-256 encryption
- 30-day automatic rotation
- Regional deployment (us-central1)
- Service account decrypt-only access

**Variables:**

```hcl
variable "key_ring_name" {
  default = "eth-validator-val-keyring"
}

variable "crypto_key_name" {
  default = "eth-validator"
}

variable "rotation_period" {
  default = "2592000s"  # 30 days
}
```

**Outputs:**

- `key_ring_id` - KMS keyring ID
- `crypto_key_id` - Crypto key ID
- `crypto_key_self_link` - Crypto key self link (for IAM)

### storage

GCS bucket for encrypted validator keys with KMS encryption.

**Resources:**

- `google_storage_bucket` - Regional GCS bucket
- `google_storage_bucket_iam_member` - IAM bindings for service account

**Key Features:**

- Customer-managed encryption (CMEK) with Cloud KMS
- Regional storage (us-central1)
- Versioning enabled
- Lifecycle rules (30-day version retention)
- Service account read/write access

**Variables:**

```hcl
variable "bucket_name" {
  default = "eth-validator-bucket"
}

variable "bucket_roles" {
  default = [
    "roles/storage.objectViewer",
    "roles/storage.objectCreator"
  ]
}
```

**Outputs:**

- `bucket_name` - GCS bucket name
- `bucket_url` - gs:// URL

### loadbalancer

(Optional) HTTP(S) load balancer for RPC access.

**Resources:**

- `google_compute_global_address` - Global static IP
- `google_compute_backend_service` - Backend service
- `google_compute_url_map` - URL routing
- `google_compute_target_http_proxy` - HTTP proxy
- `google_compute_global_forwarding_rule` - Forwarding rule

**Note:** Load balancer is optional and currently not used in single-VM setup.

## Variables Reference

### Required Variables

```hcl
# GCP Project and Region
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Resource naming
resource_prefix = "<your_resource_prefix>"

# Ansible SSH user
ansible_user = "your-username"
ssh_public_key_file = "~/.ssh/id_rsa.pub"
```

### Optional Variables

```hcl
# VM Configuration
machine_type = "n2-standard-8"  # 8 vCPU, 32GB RAM

# Disk Configuration
boot_disk = {
  size  = 50
  type  = "pd-balanced"
  image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

data_disk = {
  size = 500
  type = "pd-ssd"
}

# Network Configuration
subnet_cidr = "10.0.1.0/24"
firewall_source_ranges = ["0.0.0.0/0"]
firewall_allowed_ports = ["22", "30303", "9000"]

# KMS Configuration
kms_rotation_period = "2592000s"  # 30 days
```

## Outputs

Terraform outputs are used by Ansible for inventory generation.

```bash
# View all outputs
tofu output

# Get specific output
tofu output vm_external_ip
```

**Key Outputs:**

```hcl
vm_external_ip        = "35.239.65.134"
vm_internal_ip        = "10.0.1.2"
vm_instance_name      = "eth-validator-vm"
ansible_user          = "<ansible_user>"
kms_key_id            = "projects/.../cryptoKeys/eth-validator"
gcs_bucket_name       = "eth-validator-bucket"
service_account_email = "eth-validator-sa@..."
```

## State Management

### Local State (Default)

```bash
# State stored in terraform.tfstate
tofu show
tofu state list
```

### Remote State (Recommended for Production)

```hcl
# backend.tf
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "ethereum-validator/state"
  }
}
```

**Setup:**

```bash
# Create state bucket
gsutil mb gs://your-terraform-state-bucket
gsutil versioning set on gs://your-terraform-state-bucket

# Initialize with remote backend
tofu init -migrate-state
```

## Cost Estimation

### Monthly Costs (us-central1)

| Resource         | Specification                | Monthly Cost (USD) |
| ---------------- | ---------------------------- | ------------------ |
| Compute Instance | n2-standard-8 (8 vCPU, 32GB) | ~$250              |
| Boot Disk        | 50GB pd-balanced             | ~$2                |
| Data Disk        | 1TB pd-ssd                   | ~$85               |
| Static IP        | 1 address                    | ~$7                |
| Network Egress   | ~100GB/month                 | ~$12               |
| Cloud KMS        | 1 key + operations           | ~$1                |
| Cloud Storage    | <10GB                        | <$1                |
| **Total**        |                              | **~$358/month**    |

**Cost Optimization:**

- Use spot/preemptible instances: -60% compute cost
- Use pd-balanced instead of pd-ssd: -50% disk cost
- Use regional static IP instead of global: -60% IP cost

## Disaster Recovery

### Infrastructure Backup

```bash
# Export Terraform state
tofu state pull > terraform.tfstate.backup

# Backup encrypted keys from GCS
gsutil -m cp -r gs://eth-validator-bucket/validator-keys/ ./backup/
```

### Infrastructure Rebuild

```bash
# From backup state
tofu import google_compute_instance.main <instance-id>

# Or full destroy/recreate
tofu destroy -auto-approve
tofu apply -auto-approve
```

## Troubleshooting

### Authentication Issues

```bash
# Check current auth
gcloud auth list

# Re-authenticate
gcloud auth application-default login

# Set project
gcloud config set project YOUR_PROJECT_ID
```

### Permission Errors

```bash
# Check required APIs are enabled
gcloud services list --enabled

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable iam.googleapis.com
```

### State Lock Issues

```bash
# Force unlock (use with caution)
tofu force-unlock <LOCK_ID>
```

### VM Not Accessible

```bash
# Check firewall rules
gcloud compute firewall-rules list --filter="name~'eth-validator'"

# Check VM status
gcloud compute instances describe eth-validator-vm --zone=us-central1-a

# Check SSH connectivity
gcloud compute ssh eth-validator-vm --zone=us-central1-a
```

## Best Practices

1. **Use remote state** for production (GCS backend)
2. **Enable state locking** to prevent concurrent modifications
3. **Tag resources** for cost tracking and organization
4. **Use workspaces** for multiple environments (dev, staging, prod)
5. **Pin provider versions** in versions.tf
6. **Store tfvars in secrets manager** (not in Git)
7. **Use tflint** for Terraform linting
8. **Document changes** in commit messages
9. **Review plans** before applying
10. **Implement backup strategy** for state and resources

## Maintenance

### Update Infrastructure

```bash
# Make changes to .tf files
# Review plan
tofu plan

# Apply changes
tofu apply

# Regenerate Ansible inventory
../scripts/generate-ansible-inventory.sh
```

### Destroy Infrastructure

```bash
# Destroy all resources (DANGEROUS)
tofu destroy

# Destroy specific resource
tofu destroy -target=module.loadbalancer
```

### Upgrade Terraform Version

```bash
# Update versions.tf
required_version = ">= 1.6.0"

# Reinitialize
tofu init -upgrade
```

## Integration with Ansible

Terraform outputs are automatically converted to Ansible inventory:

```bash
# Generate inventory from Terraform outputs
./scripts/generate-ansible-inventory.sh

# This creates: ansible/inventory/hosts.yml
```

**Generated Inventory:**

```yaml
all:
  children:
    eth-validator:
      hosts:
        eth-validator-vm:
          ansible_host: "{{ ansible_host }}"
          ansible_user: "{{ ansible_user }}"

  vars:
    gcp_project_id: psychic-sensor-440111-i3
    gcp_region: us-central1
    kms_keyring_name: eth-validator-val-keyring
    kms_key_name: eth-validator
    gcs_bucket_name: eth-validator-bucket
```

## Security Considerations

1. **SSH Keys**: Use dedicated SSH keys, not personal keys
2. **Service Account**: Minimal permissions (KMS decrypt only)
3. **Firewall**: SSH restricted to your public IP
4. **KMS**: Automatic key rotation enabled (30 days)
5. **State File**: Contains sensitive data - secure it
6. **GCS Bucket**: CMEK encryption with Cloud KMS
7. **IAM**: Follow principle of least privilege

## Next Steps

After infrastructure is provisioned:

1. **Generate Ansible inventory**: `./scripts/generate-ansible-inventory.sh`
2. **Bootstrap VM**: `ansible-playbook ansible/playbooks/bootstrap_vm.yml`
3. **Deploy validator**: `ansible-playbook ansible/playbooks/deploy_validator.yml`
4. **Verify deployment**: `ansible-playbook ansible/playbooks/validate.yml`

For detailed deployment instructions, see [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).
