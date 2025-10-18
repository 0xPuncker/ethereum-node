#!/usr/bin/env bash
#
# generate-ansible-inventory.sh - Generate Ansible inventory from Terraform outputs
#
# This script reads the VM external IP from Terraform state and updates the Ansible
# inventory file with the correct IP address for SSH access.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_INVENTORY="${PROJECT_ROOT}/ansible/inventory/hosts.yml"
ANSIBLE_SECURE_DIR="${PROJECT_ROOT}/ansible/secure"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    log_error "Terraform directory not found: ${TERRAFORM_DIR}"
    exit 1
fi

if [[ ! -f "${ANSIBLE_INVENTORY}" ]]; then
    log_error "Ansible inventory not found: ${ANSIBLE_INVENTORY}"
    exit 1
fi

if [[ ! -d "${ANSIBLE_SECURE_DIR}" ]]; then
    log_info "Creating secure directory at: ${ANSIBLE_SECURE_DIR}"
    install -d -m 700 "${ANSIBLE_SECURE_DIR}"
fi

log_info "Fetching configuration from Terraform outputs..."

cd "${TERRAFORM_DIR}"

# Check if Terraform/OpenTofu state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    log_error "No Terraform state file found"
    log_error "Infrastructure has not been provisioned yet"
    log_error ""
    if command -v task &>/dev/null; then
        log_error "Provision infrastructure with:"
        log_error "  task validator:deploy:infra"
    else
        log_error "Provision infrastructure with:"
        log_error "  cd ${TERRAFORM_DIR}"
        log_error "  terraform init    # or: tofu init"
        log_error "  terraform apply   # or: tofu apply"
    fi
    exit 1
fi

# Try to get outputs, suppressing both stdout and stderr for the command check
if tofu version &>/dev/null; then
    TF_CMD="tofu"
elif terraform version &>/dev/null; then
    TF_CMD="terraform"
else
    log_error "Neither 'tofu' nor 'terraform' command found"
    log_error "Install OpenTofu or Terraform first"
    exit 1
fi

log_info "Using: ${TF_CMD}"

# Get outputs, redirect all stderr to /dev/null, only capture valid stdout
VM_IP=$("${TF_CMD}" output -raw vm_external_ip 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n')
ANSIBLE_USER=$("${TF_CMD}" output -raw ansible_user 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n')
if [[ -z "${ANSIBLE_USER}" ]] && command -v terraform &>/dev/null && [[ "${TF_CMD}" != "terraform" ]]; then
    log_warn "Fallback to terraform output for ansible_user"
    ANSIBLE_USER=$(terraform output -raw ansible_user 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n' || true)
fi
if [[ -z "${ANSIBLE_USER}" ]] && [[ -f "terraform.tfvars" ]]; then
    log_warn "Using terraform.tfvars fallback for ansible_user"
    ANSIBLE_USER=$(grep -E '^\s*ansible_user\s*=' terraform.tfvars | tail -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)
fi
if [[ -z "${ANSIBLE_USER}" ]] && [[ -f "variables.tf" ]]; then
    log_warn "Using variables.tf default for ansible_user"
    ANSIBLE_USER=$(awk '
        /variable "ansible_user"/ {found=1; next}
        found && /default/ {
            sub(/.*default[[:space:]]*=[[:space:]]*"/, "", $0);
            sub(/".*/, "", $0);
            print $0;
            exit
        }' variables.tf)
fi
if [[ -z "${ANSIBLE_USER}" ]]; then
    log_warn "ansible_user not found; defaulting to current user"
    ANSIBLE_USER="${USER:-ubuntu}"
fi
BUCKET_NAME=$("${TF_CMD}" output -raw bucket_name 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n')
KMS_KEY_ID=$("${TF_CMD}" output -raw kms_crypto_key_id 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n')

# Validate outputs
if [[ -z "${VM_IP}" ]] || [[ "${VM_IP}" == "The state file"* ]]; then
    log_error "Failed to get VM external IP from Terraform outputs"
    log_error "Infrastructure has not been provisioned yet"
    log_error ""
    log_error "Run this command first to provision infrastructure:"
    if command -v task &>/dev/null; then
        log_error "  task validator:deploy:infra"
        log_error ""
        log_error "Or separately:"
        log_error "  task tf:init"
        log_error "  task tf:apply"
    else
        log_error "  cd ${TERRAFORM_DIR}"
        log_error "  ${TF_CMD} init"
        log_error "  ${TF_CMD} apply"
    fi
    exit 1
fi

if [[ -z "${ANSIBLE_USER}" ]] || [[ "${ANSIBLE_USER}" == "The state file"* ]]; then
    log_error "Failed to get ansible_user from Terraform outputs"
    log_error "Infrastructure provisioning incomplete"
    if command -v task &>/dev/null; then
        log_error "Run: task validator:deploy:infra"
    else
        log_error "Run: cd ${TERRAFORM_DIR} && ${TF_CMD} apply"
    fi
    exit 1
fi

log_info "VM external IP: ${VM_IP}"
log_info "Ansible user: ${ANSIBLE_USER}"
log_info "GCS Bucket: ${BUCKET_NAME}"
log_info "KMS Key: ${KMS_KEY_ID}"

BACKUP_FILE="${ANSIBLE_INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)"
cp "${ANSIBLE_INVENTORY}" "${BACKUP_FILE}"
log_info "Backed up existing inventory to: ${BACKUP_FILE}"

log_info "Updating Ansible inventory..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS BSD sed
    sed -i '' -E "s/(ansible_host: ).*/\\1${VM_IP}/" "${ANSIBLE_INVENTORY}"
    sed -i '' -E "s/(ansible_user: ).*/\\1${ANSIBLE_USER}/" "${ANSIBLE_INVENTORY}"
    sed -i '' -E "s|(ansible_ssh_common_args: ).*|\\1\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes\"|" "${ANSIBLE_INVENTORY}"
else
    # GNU sed
    sed -i -E "s/(ansible_host: ).*/\\1${VM_IP}/" "${ANSIBLE_INVENTORY}"
    sed -i -E "s/(ansible_user: ).*/\\1${ANSIBLE_USER}/" "${ANSIBLE_INVENTORY}"
    sed -i -E "s|(ansible_ssh_common_args: ).*|\\1\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes\"|" "${ANSIBLE_INVENTORY}"
fi

log_info "Ansible inventory updated successfully"
log_info "Inventory file: ${ANSIBLE_INVENTORY}"

ENVRC_FILE="${PROJECT_ROOT}/.envrc"
log_info "Generating .envrc file..."

cd "${TERRAFORM_DIR}"

# Get full vm_self_link to parse project and region
VM_SELF_LINK=$("${TF_CMD}" output -raw vm_self_link 2>&1 | grep -v "Warning:" | grep -v "╷" | grep -v "│" | grep -v "╵" | tr -d '\n' || true)

if [[ -n "${VM_SELF_LINK}" ]] && [[ "${VM_SELF_LINK}" =~ ^https://www\.googleapis\.com/compute ]]; then
    # Parse from self link: https://www.googleapis.com/compute/v1/projects/{project}/zones/{zone}/instances/{instance}
    GCP_PROJECT=$(echo "${VM_SELF_LINK}" | cut -d'/' -f7)
    GCP_ZONE=$(echo "${VM_SELF_LINK}" | cut -d'/' -f9)
    GCP_REGION="${GCP_ZONE%-*}"  # Remove last part after dash (e.g., us-central1-a -> us-central1)
else
    GCP_PROJECT=""
    GCP_REGION=""
    GCP_ZONE=""
    log_warn "Could not parse GCP project/region from Terraform outputs"
fi

# Parse KMS details from KMS key ID
# Format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}
if [[ -n "${KMS_KEY_ID}" ]]; then
    KMS_LOCATION_PARSED=$(echo "${KMS_KEY_ID}" | cut -d'/' -f4)
    KMS_KEYRING_PARSED=$(echo "${KMS_KEY_ID}" | cut -d'/' -f6)
    KMS_KEY_PARSED=$(echo "${KMS_KEY_ID}" | cut -d'/' -f8)
else
    KMS_LOCATION_PARSED=""
    KMS_KEYRING_PARSED=""
    KMS_KEY_PARSED=""
fi

# Get GCP project number
GCP_PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format="value(projectNumber)" 2>/dev/null || echo "")

cat > "${ENVRC_FILE}" <<EOF
# GCP Configuration (auto-generated from Terraform outputs)
# Generated: $(date)

export GCP_PROJECT_ID="${GCP_PROJECT}"
export GCP_PROJECT_NUMBER="${GCP_PROJECT_NUMBER}"
export GCP_REGION="${GCP_REGION}"
export GCP_ZONE="${GCP_REGION}-a"

# VM Configuration
export VM_EXTERNAL_IP="${VM_IP}"
export ANSIBLE_USER="${ANSIBLE_USER}"

# Cloud KMS Configuration
export KMS_LOCATION="${KMS_LOCATION_PARSED}"
export KMS_KEYRING_NAME="${KMS_KEYRING_PARSED}"
export KMS_KEY_NAME="${KMS_KEY_PARSED}"
export KMS_KEY_ID="${KMS_KEY_ID}"

# Cloud Storage Configuration (for Terraform state backend)
export GCS_BUCKET="eth-node-terraform-state"
export GCS_PREFIX="eth-node/state"

# Validator Keys Storage Configuration
export VALIDATOR_KEYS_BUCKET="${BUCKET_NAME}"
export VALIDATOR_KEYS_PREFIX="validator-keys"

# Note: Source this file with 'source .envrc' or use direnv
EOF

log_info ".envrc file generated: ${ENVRC_FILE}"
log_info "Source it with: source .envrc"

log_info "Testing Ansible connectivity..."
cd "${PROJECT_ROOT}"

if ansible eth_validator_vm -i "${ANSIBLE_INVENTORY}" -m ping &>/dev/null; then
    log_info "Ansible ping successful!"
else
    log_warn "Ansible ping failed. This may be normal if the VM is still provisioning."
    log_warn "You can test manually with: ansible eth_validator_vm -i ${ANSIBLE_INVENTORY} -m ping"
fi

log_info "Done!"
