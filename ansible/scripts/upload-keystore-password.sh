#!/bin/bash
# Upload keystore password to GCS (KMS-encrypted)
# This creates the password file needed for validator keystores

set -euo pipefail

# Configuration
GCP_PROJECT="psychic-sensor-440111-i3"
KMS_KEYRING="eth-validator-val-keyring"
KMS_KEY="eth-validator"
KMS_LOCATION="us-central1"
GCS_BUCKET="eth-validator-bucket"
GCS_PREFIX="validator-keys/encrypted"

# Get password from inventory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY_FILE="${PROJECT_ROOT}/ansible/inventory/hosts.yml"

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "ERROR: Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Extract password from inventory
PASSWORD=$(grep 'deposit_cli_keystore_password:' "$INVENTORY_FILE" | awk '{print $2}' | tr -d '"')

if [ -z "$PASSWORD" ]; then
    echo "ERROR: Could not extract password from inventory"
    exit 1
fi

echo "Found keystore password in inventory"

# Get list of keystores from GCS
echo "Fetching keystore list from GCS..."
KEYSTORES=$(gcloud storage ls "gs://$GCS_BUCKET/$GCS_PREFIX/" --project="$GCP_PROJECT" 2>/dev/null | grep '\.json\.enc$' || echo "")

if [ -z "$KEYSTORES" ]; then
    echo "ERROR: No keystores found in GCS bucket"
    echo "Location: gs://$GCS_BUCKET/$GCS_PREFIX/"
    exit 1
fi

# Create password file for each keystore
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

for KEYSTORE_PATH in $KEYSTORES; do
    KEYSTORE_NAME=$(basename "$KEYSTORE_PATH" .json.enc)
    PASSWORD_FILE="${TEMP_DIR}/${KEYSTORE_NAME}.txt"
    ENCRYPTED_FILE="${TEMP_DIR}/${KEYSTORE_NAME}.txt.enc"

    echo "Processing keystore: $KEYSTORE_NAME"

    # Create password file
    echo -n "$PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    # Encrypt password file with KMS
    echo "  Encrypting password file..."
    gcloud kms encrypt \
        --project="$GCP_PROJECT" \
        --location="$KMS_LOCATION" \
        --keyring="$KMS_KEYRING" \
        --key="$KMS_KEY" \
        --plaintext-file="$PASSWORD_FILE" \
        --ciphertext-file="$ENCRYPTED_FILE"

    # Upload encrypted password to GCS
    echo "  Uploading to GCS..."
    gcloud storage cp "$ENCRYPTED_FILE" \
        "gs://$GCS_BUCKET/$GCS_PREFIX/${KEYSTORE_NAME}.txt.enc" \
        --project="$GCP_PROJECT"

    echo "  ✓ Password file uploaded: ${KEYSTORE_NAME}.txt.enc"
done

echo ""
echo "✓ All keystore passwords uploaded successfully"
echo "  Bucket: gs://$GCS_BUCKET/$GCS_PREFIX/"
echo ""
echo "Next step: Restart validator service to load keys"
echo "  ssh <host> 'sudo systemctl restart validator'"
