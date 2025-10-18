#!/bin/bash
# Ethereum Validator Infrastructure Provisioning Script
#
# Prerequisites:
#   1. Terraform infrastructure deployed: task validator:deploy:infra (or terraform apply)
#   2. Ansible 2.14+ installed
#   3. SSH access to target VM configured
#
# Usage:
#   sudo ./scripts/provision.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

# Logging
LOG_FILE="/tmp/ethereum-validator-provision.log"
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Ethereum Validator Infrastructure Provisioning        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Started at: $(date)"
log_info "Log file: ${LOG_FILE}"
echo ""

# Prerequisite checks
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Checking Prerequisites"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MISSING_REQUIRED=()
MISSING_RECOMMENDED=()

# Required tools
log_info "Required tools:"

# 1. Ansible
if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(ansible --version | head -n1 | sed -E 's/.*\[core ([0-9.]+)\].*/\1/' || ansible --version | head -n1 | awk '{print $2}')
    log_success "  ✓ Ansible ${ANSIBLE_VERSION}"
else
    log_error "  ✗ Ansible not found"
    MISSING_REQUIRED+=("ansible")
fi

# 2. Terraform OR OpenTofu
if command -v tofu &> /dev/null; then
    TOFU_VERSION=$(tofu version | head -n1 | awk '{print $2}')
    log_success "  ✓ OpenTofu ${TOFU_VERSION}"
elif command -v terraform &> /dev/null; then
    TERRAFORM_VERSION=$(terraform version | head -n1 | awk '{print $2}')
    log_success "  ✓ Terraform ${TERRAFORM_VERSION}"
else
    log_error "  ✗ Neither OpenTofu nor Terraform found"
    MISSING_REQUIRED+=("terraform-or-tofu")
fi

echo ""
log_info "Recommended tools:"

# 3. direnv (optional but recommended)
if command -v direnv &> /dev/null; then
    DIRENV_VERSION=$(direnv version 2>/dev/null || echo "unknown")
    log_success "  ✓ direnv ${DIRENV_VERSION}"
else
    log_warning "  ⚠ direnv not found (recommended for environment management)"
    MISSING_RECOMMENDED+=("direnv")
fi

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    log_success "  ✓ Node.js ${NODE_VERSION}"
else
    log_warning "  ⚠ Node.js not found (recommended for development tools)"
    MISSING_RECOMMENDED+=("node")
fi

if command -v pre-commit &> /dev/null; then
    PRECOMMIT_VERSION=$(pre-commit --version | awk '{print $2}')
    log_success "  ✓ pre-commit ${PRECOMMIT_VERSION}"
else
    log_warning "  ⚠ pre-commit not found (recommended for git hooks)"
    MISSING_RECOMMENDED+=("pre-commit")
fi

if command -v task &> /dev/null; then
    TASK_VERSION=$(task --version | head -n1 | awk '{print $3}')
    log_success "  ✓ Task ${TASK_VERSION}"
else
    log_warning "  ⚠ task not found (recommended for task automation)"
    MISSING_RECOMMENDED+=("task")
fi

echo ""

# Handle missing required tools
if [ ${#MISSING_REQUIRED[@]} -gt 0 ]; then
    log_error "Missing required tools: ${MISSING_REQUIRED[*]}"
    echo ""
    log_info "Installation instructions:"

    for tool in "${MISSING_REQUIRED[@]}"; do
        case $tool in
            ansible)
                echo "  • Ansible:"
                echo "    Ubuntu/Debian: sudo apt install ansible"
                echo "    macOS: brew install ansible"
                echo "    Docs: https://docs.ansible.com/ansible/latest/installation_guide/"
                ;;
            terraform-or-tofu)
                echo "  • OpenTofu (recommended):"
                echo "    macOS: brew install opentofu"
                echo "    Linux: https://opentofu.org/docs/intro/install/"
                echo ""
                echo "  • OR Terraform:"
                echo "    macOS: brew install terraform"
                echo "    Linux: https://developer.hashicorp.com/terraform/install"
                ;;
        esac
        echo ""
    done

    exit 1
fi

if [ ${#MISSING_RECOMMENDED[@]} -gt 0 ]; then
    log_warning "Missing recommended tools: ${MISSING_RECOMMENDED[*]}"
    echo ""
    log_info "Optional installation instructions:"

    for tool in "${MISSING_RECOMMENDED[@]}"; do
        case $tool in
            direnv)
                echo "  • direnv: brew install direnv (macOS) or apt install direnv (Linux)"
                ;;
            node)
                echo "  • Node.js: brew install node (macOS) or apt install nodejs (Linux)"
                ;;
            pre-commit)
                echo "  • pre-commit: pip install pre-commit or brew install pre-commit"
                ;;
            task)
                echo "  • Task: brew install go-task (macOS) or snap install task (Linux)"
                ;;
        esac
    done
    echo ""
    log_info "You can continue without these tools, but they are recommended for development"
    echo ""
fi

log_success "All required prerequisites are installed"
echo ""

# Check if Task is available - REQUIRED for orchestration
if ! command -v task &> /dev/null; then
    log_error "Task is required for orchestration but not found"
    log_error "Install Task with:"
    log_error "  macOS: brew install go-task"
    log_error "  Linux: snap install task --classic"
    log_error "  or see: https://taskfile.dev/installation/"
    exit 1
fi

log_info "Using Task for orchestration"
echo ""

# Run inventory generation to create .envrc
log_info "Generating Ansible inventory and .envrc from Terraform state..."
if bash "${ANSIBLE_DIR}/scripts/generate-ansible-inventory.sh"; then
    log_success "Ansible inventory and .envrc generated successfully."
else
    log_error "Failed to generate Ansible inventory. This is a critical step."
    log_error "Ensure Terraform has been applied and the state file is valid."
    exit 1
fi
echo ""

# Run GCP pre-flight checks (auto-generates .envrc if needed)
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "GCP Environment Setup & Validation"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

GCP_PREFLIGHT_SCRIPT="${SCRIPT_DIR}/gcp-preflight.sh"

if [ -f "${GCP_PREFLIGHT_SCRIPT}" ]; then
    # Run pre-flight checks (will auto-generate .envrc if missing)
    if bash "${GCP_PREFLIGHT_SCRIPT}"; then
        log_success "GCP environment configured and validated successfully"
    else
        log_error "GCP pre-flight setup failed"
        log_error ""
        log_error "Common issues:"
        log_error "  1. Not authenticated with GCP: gcloud auth login"
        log_error "  2. GCP project not configured: gcloud config set project PROJECT_ID"
        log_error "  3. Required GCP APIs not enabled"
        log_error "  4. Insufficient GCP permissions"
        log_error ""
        exit 1
    fi
else
    log_error "GCP pre-flight script not found: ${GCP_PREFLIGHT_SCRIPT}"
    log_info "Proceeding without GCP environment validation (not recommended)"
fi

echo ""

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Running Full Validator Deployment"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "${PROJECT_ROOT}"

log_info "Starting deployment..."
echo ""

if task validator:deploy:all; then
    log_success "Complete validator deployment successful!"
else
    log_error "Validator deployment failed"
    log_info "Check logs: ${LOG_FILE}"
    log_info "Run with verbose output: task ansible:deploy-verbose"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Provisioning Complete!                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_success "All infrastructure components are now deployed!"
echo ""

REMOTE_HOST=$(grep 'ansible_host:' inventory/hosts.yml | head -n1 | awk '{print $2}')

log_info "📊 Infrastructure Status:"
echo "  • Disk: /validator mounted and configured"
echo "  • Users: execution, consensus, validator created"
echo "  • Security: SSH hardened, firewall active"
echo "  • Clients: Nethermind + Nimbus installed"
echo "  • Services: systemd services created (not started yet)"
echo ""

log_info "📝 Next Steps:"
echo ""
if [ "$USE_TASK" = true ]; then
    echo "  1. Start the validator:"
    echo "     task validator:start"
    echo "     (or: sudo ./scripts/start-validator.sh)"
    echo ""
    echo "  2. Check health:"
    echo "     ./scripts/check-health.sh"
    echo ""
    echo "  3. Monitor sync progress:"
    echo "     task validator:logs-execution    # Execution client logs"
    echo "     task validator:logs-consensus    # Consensus client logs"
    echo "     task validator:logs              # Validator client logs"
    echo "     task validator:logs-all          # All services combined"
    echo ""
    echo "  4. SSH to validator VM:"
    echo "     task vm:ssh"
else
    echo "  1. Start the validator:"
    echo "     sudo ./scripts/start-validator.sh"
    echo ""
    echo "  2. Check health:"
    echo "     ./scripts/check-health.sh"
    echo ""
    echo "  3. Monitor sync progress:"
    echo "     ssh ${REMOTE_HOST} 'sudo journalctl -fu execution'"
    echo "     ssh ${REMOTE_HOST} 'sudo journalctl -fu consensus'"
    echo ""
fi

log_info "Log file saved to: ${LOG_FILE}"
echo ""
log_success "Done! ✨"
