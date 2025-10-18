#!/usr/bin/env bash
#
# import-kms-resources.sh - Import existing GCP KMS resources into Terraform state
#
# This script checks if KMS keyring and crypto key already exist in GCP,
# and imports them into Terraform state if they do.
#
# Usage:
#   ./scripts/import-kms-resources.sh
#
# Prerequisites:
#   - gcloud CLI authenticated
#   - .envrc file with GCP_PROJECT, GCP_REGION, KMS_KEYRING, KMS_KEY
#   - Terraform/OpenTofu installed

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
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

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

# Load environment variables
if [ -f "${PROJECT_ROOT}/.envrc" ]; then
    log_info "Loading environment variables from .envrc"
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.envrc"
else
    log_info ".envrc file not found - this is likely the first deployment"
    log_info "Skipping KMS import check (nothing to import on first run)"
    log_success "Import check complete (no existing resources to import)"
    exit 0
fi

# Validate required variables
REQUIRED_VARS=("GCP_PROJECT" "KMS_LOCATION" "KMS_KEYRING" "KMS_KEY")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_warning "Missing required environment variables: ${MISSING_VARS[*]}"
    log_info "Skipping KMS import check (.envrc incomplete)"
    log_success "Import check complete (no existing resources to import)"
    exit 0
fi

log_info "Configuration:"
log_info "  Project: ${GCP_PROJECT}"
log_info "  Location: ${KMS_LOCATION}"
log_info "  Keyring: ${KMS_KEYRING}"
log_info "  Crypto Key: ${KMS_KEY}"
echo ""

if command -v tofu &>/dev/null; then
    TF_CMD="tofu"
elif command -v terraform &>/dev/null; then
    TF_CMD="terraform"
else
    log_error "Neither 'tofu' nor 'terraform' command found"
    exit 1
fi

log_info "Using: ${TF_CMD}"

cd "${TERRAFORM_DIR}"

KEYRING_PATH="projects/${GCP_PROJECT}/locations/${KMS_LOCATION}/keyRings/${KMS_KEYRING}"
KEYRING_ADDRESS="module.kms.google_kms_key_ring.this[0]"
CREATE_KEY_RING_IMPORT=$(echo "${TF_VAR_kms_create_key_ring:-true}" | tr '[:upper:]' '[:lower:]')

if [ "${CREATE_KEY_RING_IMPORT}" != "true" ]; then
    log_info "Terraform configured to reuse an existing key ring (kms_create_key_ring=false); skipping key ring import."
else
    log_info "Checking if KMS keyring exists in GCP..."

    if gcloud kms keyrings describe "${KMS_KEYRING}" \
        --location="${KMS_LOCATION}" \
        --project="${GCP_PROJECT}" &>/dev/null; then

        log_success "Keyring exists in GCP: ${KEYRING_PATH}"
        if "${TF_CMD}" state show "${KEYRING_ADDRESS}" &>/dev/null; then
            log_warning "Keyring already in Terraform state, skipping import"
        else
            log_info "Importing keyring into Terraform state..."
            if "${TF_CMD}" import "${KEYRING_ADDRESS}" "${KEYRING_PATH}"; then
                log_success "Keyring imported successfully"
            else
                log_error "Failed to import keyring"
                exit 1
            fi
        fi
    else
        log_info "Keyring does not exist in GCP yet"
    fi
fi

CRYPTO_KEY_PATH="${KEYRING_PATH}/cryptoKeys/${KMS_KEY}"
CRYPTO_KEY_ADDRESS="module.kms.google_kms_crypto_key.this[0]"
CREATE_CRYPTO_KEY_IMPORT=$(echo "${TF_VAR_kms_create_crypto_key:-true}" | tr '[:upper:]' '[:lower:]')

if [ "${CREATE_CRYPTO_KEY_IMPORT}" != "true" ]; then
    log_info "Terraform configured to reuse an existing crypto key (kms_create_crypto_key=false); skipping crypto key import."
else
    log_info "Checking if KMS crypto key exists in GCP..."

    if gcloud kms keys describe "${KMS_KEY}" \
        --keyring="${KMS_KEYRING}" \
        --location="${KMS_LOCATION}" \
        --project="${GCP_PROJECT}" &>/dev/null; then

        log_success "Crypto key exists in GCP: ${CRYPTO_KEY_PATH}"

        if "${TF_CMD}" state show "${CRYPTO_KEY_ADDRESS}" &>/dev/null; then
            log_warning "Crypto key already in Terraform state, skipping import"
        else
            log_info "Importing crypto key into Terraform state..."
            if "${TF_CMD}" import "${CRYPTO_KEY_ADDRESS}" "${CRYPTO_KEY_PATH}"; then
                log_success "Crypto key imported successfully"
            else
                log_error "Failed to import crypto key"
                exit 1
            fi
        fi
    else
        log_info "Crypto key does not exist in GCP yet"
    fi
fi

echo ""
log_success "KMS resource import check complete!"
log_info "You can now run: task tf:apply"
