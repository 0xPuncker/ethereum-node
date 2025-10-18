#!/usr/bin/env bash
# Pre-flight checks for GCP resources used by the validator stack.
# Expects required env vars to be loaded (e.g., via .envrc / direnv).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVRC_FILE="${PROJECT_ROOT}/.envrc"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

if [[ -f "${ENVRC_FILE}" ]]; then
  log_info "Loading environment variables from .envrc..."
  source "${ENVRC_FILE}"
  log_success "Environment variables loaded."
  echo ""
else
  log_warn ".envrc not found in project root; relying on current shell environment."
  echo ""
fi

GCS_BUCKET="${GCS_BUCKET:-eth-node-terraform-state}"
GCS_PREFIX="${GCS_PREFIX:-eth-node/state}"

required_env_vars=(
  "GCP_PROJECT_ID"
  "GCP_PROJECT_NUMBER"
  "GCP_REGION"
  "KMS_KEYRING_NAME"
  "KMS_KEY_NAME"
  "KMS_LOCATION"
)

missing_vars=()
for var in "${required_env_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if (( ${#missing_vars[@]} > 0 )); then
  log_error "Missing required environment variables: ${missing_vars[*]}"
  log_info  "Export them manually or populate .envrc before rerunning."
  exit 1
fi

GCP_ZONE="${GCP_ZONE:-}"

log_info "Project     : ${GCP_PROJECT_ID}"
log_info "Project No. : ${GCP_PROJECT_NUMBER}"
log_info "Region      : ${GCP_REGION}"
log_info "Zone        : ${GCP_ZONE:-<not set>}"
log_info "KMS Target  : ${KMS_LOCATION}/${KMS_KEYRING_NAME}/${KMS_KEY_NAME}"
log_info "State Bucket: gs://${GCS_BUCKET}/${GCS_PREFIX}"
echo ""

if ! command -v gcloud >/dev/null 2>&1; then
  log_error "gcloud CLI not found. Install Google Cloud SDK first."
  exit 1
fi

GCLOUD_ACCOUNT=$(gcloud auth list --format="value(account)" --filter="status:ACTIVE" 2>/dev/null || true)
if [[ -z "${GCLOUD_ACCOUNT}" ]]; then
  log_warn "No active gcloud account detected."
  log_info "Run 'gcloud auth login' (and optionally 'gcloud auth application-default login') before retrying."
  exit 1
fi
log_success "Active gcloud account: ${GCLOUD_ACCOUNT}"

gcloud config set project "${GCP_PROJECT_ID}" >/dev/null
log_success "Configured gcloud project."

log_info "Enabling required APIs (idempotent)..."
gcloud services enable \
  compute.googleapis.com \
  cloudkms.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project "${GCP_PROJECT_ID}" >/dev/null
log_success "API checks complete."

log_info "Validating Terraform backend bucket 'gs://${GCS_BUCKET}'..."
if gcloud storage buckets describe "gs://${GCS_BUCKET}" --project "${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log_success "Bucket exists."
else
  log_warn "Bucket gs://${GCS_BUCKET} not found."
  log_warn "Terraform backend expects this bucket; create it before running 'tofu init'."
  log_info "Example: gcloud storage buckets create gs://${GCS_BUCKET} --project=${GCP_PROJECT_ID} --location=${GCP_REGION}"
fi

log_info "Ensuring KMS keyring '${KMS_KEYRING_NAME}' exists..."
if gcloud kms keyrings describe "${KMS_KEYRING_NAME}" \
    --location "${KMS_LOCATION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log_success "Keyring present."
else
  gcloud kms keyrings create "${KMS_KEYRING_NAME}" \
    --location "${KMS_LOCATION}" \
    --project "${GCP_PROJECT_ID}"
  log_success "Keyring created."
fi

log_info "Ensuring KMS key '${KMS_KEY_NAME}' exists..."
if gcloud kms keys describe "${KMS_KEY_NAME}" \
    --keyring "${KMS_KEYRING_NAME}" \
    --location "${KMS_LOCATION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log_success "Key present."
else
  gcloud kms keys create "${KMS_KEY_NAME}" \
    --keyring "${KMS_KEYRING_NAME}" \
    --location "${KMS_LOCATION}" \
    --purpose encryption \
    --project "${GCP_PROJECT_ID}"
  log_success "Key created."
fi

COMPUTE_SA="service-${GCP_PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com"
log_info "Granting KMS crypto roles to ${COMPUTE_SA}..."
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --quiet >/dev/null
log_success "IAM binding ensured."

if [[ -n "${GCP_ZONE}" ]]; then
  log_info "Listing PD-SSD disks in region ${GCP_REGION} (informational)..."
  gcloud compute disks list \
    --project "${GCP_PROJECT_ID}" \
    --filter="region:${GCP_REGION} AND type~'pd-ssd'" \
    --format="table(name,sizeGb,type,zone,status)" || true
fi

echo ""
log_success "GCP pre-flight checks complete."
log_info "Next steps:"
echo "  • Verify gcloud auth: gcloud auth list"
echo "  • Ensure terraform backend bucket exists if warning appeared."
echo "  • Continue with terraform/tofu init & apply."
echo ""
