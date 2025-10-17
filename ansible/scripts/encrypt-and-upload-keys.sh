#!/bin/bash
# Encrypt Validator Keys with Cloud KMS and Upload to GCS
# Run this locally to encrypt your validator keystores before deployment
#
# Prerequisites:
# - gcloud CLI installed and authenticated
# - Validator keystores generated (via EthStaker deposit-cli)
# - Terraform infrastructure deployed (KMS + GCS bucket)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration (get from Terraform outputs)
get_terraform_config() {
    cd "$(dirname "$0")/../terraform" || exit 1

    GCP_PROJECT=$(terraform output -raw project_id 2>/dev/null || echo "")
    KMS_KEYRING=$(terraform output -raw kms_keyring_name 2>/dev/null || echo "eth-validator-val-keyring")
    KMS_KEY=$(terraform output -raw kms_key_name 2>/dev/null || echo "eth-validator")
    KMS_LOCATION=$(terraform output -raw region 2>/dev/null || echo "us-central1")
    GCS_BUCKET=$(terraform output -raw gcs_bucket_name 2>/dev/null || echo "eth-validator-bucket")

    if [ -z "$GCP_PROJECT" ]; then
        log_error "Could not determine GCP project from Terraform"
        log_info "Please ensure Terraform is initialized and deployed"
        exit 1
    fi

    cd - > /dev/null
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Encrypt Validator Keys with Cloud KMS                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed"
    log_info "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed"
    log_info "Install from: https://www.terraform.io/downloads"
    exit 1
fi

log_success "Prerequisites check passed"
echo ""

# Get Terraform configuration
log_info "Loading configuration from Terraform..."
get_terraform_config

log_success "Configuration loaded:"
echo "  • GCP Project: $GCP_PROJECT"
echo "  • KMS Keyring: $KMS_KEYRING"
echo "  • KMS Key: $KMS_KEY"
echo "  • KMS Location: $KMS_LOCATION"
echo "  • GCS Bucket: gs://$GCS_BUCKET"
echo ""

# Prompt for keystore directory
read -p "Enter path to validator keystores directory: " KEYSTORE_DIR

if [ ! -d "$KEYSTORE_DIR" ]; then
    log_error "Directory not found: $KEYSTORE_DIR"
    exit 1
fi

# Find keystore files
KEYSTORE_FILES=$(find "$KEYSTORE_DIR" -name "keystore-*.json" -type f)
KEYSTORE_COUNT=$(echo "$KEYSTORE_FILES" | grep -c "keystore" || echo "0")

if [ "$KEYSTORE_COUNT" -eq 0 ]; then
    log_error "No keystore files found in $KEYSTORE_DIR"
    log_info "Expected files: keystore-*.json"
    exit 1
fi

log_success "Found $KEYSTORE_COUNT keystore file(s)"
echo ""

# Create temporary encryption directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Encrypting keystores with Cloud KMS..."
echo ""

ENCRYPTED_COUNT=0

for KEYSTORE in $KEYSTORE_FILES; do
    BASENAME=$(basename "$KEYSTORE")
    ENCRYPTED_FILE="$TEMP_DIR/${BASENAME}.enc"

    log_info "Encrypting: $BASENAME"

    # Encrypt with Cloud KMS
    gcloud kms encrypt \
        --project="$GCP_PROJECT" \
        --location="$KMS_LOCATION" \
        --keyring="$KMS_KEYRING" \
        --key="$KMS_KEY" \
        --plaintext-file="$KEYSTORE" \
        --ciphertext-file="$ENCRYPTED_FILE" \
        > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Encrypted: $BASENAME → ${BASENAME}.enc"
        ((ENCRYPTED_COUNT++))
    else
        log_error "Failed to encrypt: $BASENAME"
    fi
done

echo ""
log_success "Successfully encrypted $ENCRYPTED_COUNT keystore(s)"
echo ""

# Upload to GCS
log_info "Uploading encrypted keystores to GCS..."
echo ""

GCS_PREFIX="validator-keys/encrypted"

gcloud storage cp "$TEMP_DIR"/*.enc "gs://$GCS_BUCKET/$GCS_PREFIX/" \
    --project="$GCP_PROJECT" \
    2>&1 | while read line; do log_info "$line"; done

if [ $? -eq 0 ]; then
    log_success "All encrypted keystores uploaded to GCS"
    echo ""
    log_info "📍 Location: gs://$GCS_BUCKET/$GCS_PREFIX/"
else
    log_error "Failed to upload to GCS"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Encryption Complete!                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_success "Your validator keys are now encrypted and stored securely!"
echo ""
log_info "📝 Next Steps:"
echo "  1. Start validator service:"
echo "     sudo ./scripts/start-validator.sh"
echo ""
echo "  2. Keys will be automatically:"
echo "     • Downloaded from GCS on validator startup"
echo "     • Decrypted using Cloud KMS"
echo "     • Stored in memory-only tmpfs"
echo "     • Wiped from memory on validator shutdown"
echo ""

log_info "🔒 Security Features:"
echo "  • Keys encrypted at rest with Cloud KMS"
echo "  • Decrypted keys never touch disk"
echo "  • Automatic key rotation (30 days)"
echo "  • Audit logging for all KMS operations"
echo ""

log_success "Done! ✨"
