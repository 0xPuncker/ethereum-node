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

# Validate Terraform directory exists
if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    log_error "Terraform directory not found: ${TERRAFORM_DIR}"
    exit 1
fi

# Validate Ansible inventory exists
if [[ ! -f "${ANSIBLE_INVENTORY}" ]]; then
    log_error "Ansible inventory not found: ${ANSIBLE_INVENTORY}"
    exit 1
fi

log_info "Fetching configuration from Terraform outputs..."

# Get values from Terraform
cd "${TERRAFORM_DIR}"
VM_IP=$(tofu output -raw vm_external_ip 2>/dev/null)
ANSIBLE_USER=$(tofu output -raw ansible_user 2>/dev/null)

if [[ -z "${VM_IP}" ]]; then
    log_error "Failed to get VM external IP from Terraform"
    log_error "Make sure Terraform has been applied successfully"
    exit 1
fi

if [[ -z "${ANSIBLE_USER}" ]]; then
    log_error "Failed to get ansible_user from Terraform"
    log_error "Make sure Terraform has been applied successfully"
    exit 1
fi

log_info "VM external IP: ${VM_IP}"
log_info "Ansible user: ${ANSIBLE_USER}"

# Backup existing inventory
BACKUP_FILE="${ANSIBLE_INVENTORY}.backup.$(date +%Y%m%d_%H%M%S)"
cp "${ANSIBLE_INVENTORY}" "${BACKUP_FILE}"
log_info "Backed up existing inventory to: ${BACKUP_FILE}"

# Update inventory with values from Terraform
log_info "Updating Ansible inventory..."

# Use sed to replace template variables with Terraform output values
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/ansible_host: .*/ansible_host: ${VM_IP}/" "${ANSIBLE_INVENTORY}"
    sed -i '' "s/ansible_user: .*/ansible_user: ${ANSIBLE_USER}/" "${ANSIBLE_INVENTORY}"
else
    # Linux
    sed -i "s/ansible_host: .*/ansible_host: ${VM_IP}/" "${ANSIBLE_INVENTORY}"
    sed -i "s/ansible_user: .*/ansible_user: ${ANSIBLE_USER}/" "${ANSIBLE_INVENTORY}"
fi

log_info "Ansible inventory updated successfully"
log_info "Inventory file: ${ANSIBLE_INVENTORY}"

# Test connectivity
log_info "Testing Ansible connectivity..."
cd "${PROJECT_ROOT}"

if ansible eth-validator-vm -i "${ANSIBLE_INVENTORY}" -m ping &>/dev/null; then
    log_info "Ansible ping successful!"
else
    log_warn "Ansible ping failed. This may be normal if the VM is still provisioning."
    log_warn "You can test manually with: ansible eth-validator-vm -i ${ANSIBLE_INVENTORY} -m ping"
fi

log_info "Done!"
