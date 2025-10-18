#!/bin/bash
# Upload keystore password to GCS (KMS-encrypted)
# This creates the password file needed for validator keystores

set -euo pipefail

# Configuration (can be overridden by environment variables)
GCP_PROJECT="${GCP_PROJECT_ID:-psychic-sensor-440111-i3}"
KMS_KEYRING="${KMS_KEYRING_NAME:-eth-validator-keyring}"
KMS_KEY="${KMS_KEY_NAME:-eth-validator}"
KMS_LOCATION="${KMS_LOCATION:-us-central1}"
VALIDATOR_KEYS_BUCKET="${VALIDATOR_KEYS_BUCKET:-eth-validator-bucket}"
VALIDATOR_KEYS_PREFIX="${VALIDATOR_KEYS_PREFIX:-validator-keys/encrypted}"

# Get password from inventory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY_FILE="${PROJECT_ROOT}/ansible/inventory/hosts.yml"

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "ERROR: Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

PASSWORD=$(grep 'deposit_cli_keystore_password:' "$INVENTORY_FILE" | awk '{print $2}' | tr -d '"')

if [ -z "$PASSWORD" ]; then
    echo "ERROR: Could not extract password from inventory"
    exit 1
fi

echo "Found keystore password in inventory"

# Get list of keystores from GCS
echo "Fetching keystore list from GCS..."
KEYSTORES=$(gcloud storage ls "gs://$VALIDATOR_KEYS_BUCKET/$VALIDATOR_KEYS_PREFIX/" --project="$GCP_PROJECT" 2>/dev/null | grep '\.json\.enc$' || echo "")

if [ -z "$KEYSTORES" ]; then
    echo "ERROR: No keystores found in GCS bucket"
    echo "Location: gs://$VALIDATOR_KEYS_BUCKET/$VALIDATOR_KEYS_PREFIX/"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

for KEYSTORE_PATH in $KEYSTORES; do
    KEYSTORE_NAME=$(basename "$KEYSTORE_PATH" .json.enc)
    PASSWORD_FILE="${TEMP_DIR}/${KEYSTORE_NAME}.txt"
    ENCRYPTED_FILE="${TEMP_DIR}/${KEYSTORE_NAME}.txt.enc"

    echo "Processing keystore: $KEYSTORE_NAME"

    echo -n "$PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    echo "  Encrypting password file..."
    gcloud kms encrypt \
        --project="$GCP_PROJECT" \
        --location="$KMS_LOCATION" \
        --keyring="$KMS_KEYRING" \
        --key="$KMS_KEY" \
        --plaintext-file="$PASSWORD_FILE" \
        --ciphertext-file="$ENCRYPTED_FILE"

    echo "  Uploading to GCS..."
    gcloud storage cp "$ENCRYPTED_FILE" \
        "gs://$VALIDATOR_KEYS_BUCKET/$VALIDATOR_KEYS_PREFIX/${KEYSTORE_NAME}.txt.enc" \
        --project="$GCP_PROJECT"

    echo "  ✓ Password file uploaded: ${KEYSTORE_NAME}.txt.enc"
done

echo ""
echo "✓ All keystore passwords uploaded successfully"
echo "  Bucket: gs://$VALIDATOR_KEYS_BUCKET/$VALIDATOR_KEYS_PREFIX/"
echo ""
echo "Next step: Restart validator service to load keys"
echo "  ssh <host> 'sudo systemctl restart validator'"
