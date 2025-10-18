# KMS-Encrypted Validator Key Management

## Overview

This implementation uses **Google Cloud KMS** to encrypt Ethereum validator keystores, ensuring private keys are never stored in plaintext. Decrypted keys exist only in memory (tmpfs) during validator operation.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                   Key Lifecycle                            │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  1. Generate Keys                                          │
│     └─► EthStaker deposit-cli (local)                      │
│         Output: keystore-*.json + password                 │
│                                                            │
│  2. Encrypt with KMS                                       │
│     └─► ./scripts/encrypt-and-upload-keys.sh              │
│         • Encrypts with Cloud KMS key                      │
│         • Uploads to GCS bucket                            │
│         • Original keys can be deleted from local machine  │
│                                                            │
│  3. Validator Startup (ExecStartPre)                       │
│     └─► /usr/local/bin/decrypt-validator-keys.sh          │
│         • Downloads encrypted keys from GCS                │
│         • Decrypts using Cloud KMS                         │
│         • Stores in tmpfs (RAM-only, no disk)              │
│         • Sets strict permissions (700, validator:validator)│
│                                                            │
│  4. Validator Runtime                                      │
│     └─► validator.service reads keys from tmpfs           │
│         • Keys accessible only to validator user           │
│         • Keys never written to disk                       │
│                                                            │
│  5. Validator Shutdown (ExecStopPost)                      │
│     └─► /usr/local/bin/cleanup-validator-keys.sh          │
│         • Securely wipes keys with shred                   │
│         • Removes all traces from memory                   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Security Features

### Encryption at Rest
- **Cloud KMS**: Industry-standard encryption (AES-256)
- **Key Rotation**: Automatic 30-day rotation
- **Access Control**: IAM policies restrict KMS key access
- **Audit Logging**: All KMS operations logged to Cloud Logging

### Encryption in Transit
- **TLS**: All GCS and KMS API calls use TLS 1.3
- **Service Account**: VM uses dedicated service account with minimal permissions

### Memory-Only Storage
- **tmpfs Mount**: Decrypted keys stored in RAM, never on disk
- **Size Limit**: 100MB tmpfs (sufficient for thousands of keys)
- **Permissions**: 700 (owner-only access)
- **Auto-Wipe**: Keys wiped on service stop

### Secure Deletion
- **shred**: Overwrites key data 3 times before deletion
- **Zero-Fill**: Final pass writes zeros to memory locations
- **Verification**: Deletion verified in systemd logs

## Prerequisites

1. **Terraform Infrastructure Deployed**
   ```bash
   cd terraform
   terraform apply
   ```
   This creates:
   - Cloud KMS keyring and crypto key
   - GCS bucket (encrypted with KMS key)
   - Service account with KMS decrypt permissions

2. **Validator Keystores Generated**
   ```bash
   # Download EthStaker deposit-cli
   wget https://github.com/ethstaker/ethstaker-deposit-cli/releases/download/v1.2.2/ethstaker_deposit-cli-b13dcb9-linux-amd64.tar.gz
   tar xvf staking_deposit-cli-*-linux-amd64.tar.gz
   cd staking_deposit-cli-*-linux-amd64

   # Generate keys (example for 1 validator on Holesky)
   ./deposit new-mnemonic \
     --num_validators 1 \
     --chain holesky \
     --eth1_withdrawal_address <YOUR_ETH_ADDRESS>

   # Output: validator_keys/keystore-*.json
   ```

## Workflow

### Step 1: Encrypt and Upload Keys

From your local machine (not the validator VM):

```bash
# Ensure you're authenticated with gcloud
gcloud auth application-default login

# Run encryption script
./scripts/encrypt-and-upload-keys.sh
```

**Prompt:**
```
Enter path to validator keystores directory: /path/to/validator_keys
```

**Output:**
```
╔════════════════════════════════════════════════════════════╗
║     Encrypt Validator Keys with Cloud KMS                 ║
╚════════════════════════════════════════════════════════════╝

[INFO] Loading configuration from Terraform...
[SUCCESS] Configuration loaded:
  • GCP Project: psychic-sensor-440111-i3
  • KMS Keyring: eth-validator-val-keyring
  • KMS Key: eth-validator
  • KMS Location: us-central1
  • GCS Bucket: gs://eth-validator-bucket

[SUCCESS] Found 1 keystore file(s)

[INFO] Encrypting keystores with Cloud KMS...
[SUCCESS] Encrypted: keystore-m_12381_3600_0_0_0.json → keystore-m_12381_3600_0_0_0.json.enc

[INFO] Uploading encrypted keystores to GCS...
[SUCCESS] All encrypted keystores uploaded to GCS

╔════════════════════════════════════════════════════════════╗
║              Encryption Complete!                          ║
╚════════════════════════════════════════════════════════════╝
```

### Step 2: Deploy Validator Infrastructure

```bash
# Provision infrastructure (includes KMS setup)
sudo ./scripts/provision.sh
```

This runs the `kms_secrets` Ansible role which:
- Installs gcloud CLI on VM
- Creates tmpfs mount at `/run/validator-keys`
- Deploys decryption/cleanup scripts
- Configures systemd service hooks

### Step 3: Start Validator

```bash
# Start validator (keys automatically decrypted)
sudo ./scripts/start-validator.sh
```

**What Happens:**
1. `validator.service` starts
2. `ExecStartPre` runs `/usr/local/bin/decrypt-validator-keys.sh`
3. Script downloads encrypted keys from GCS
4. Script decrypts keys using Cloud KMS
5. Keys stored in `/run/validator-keys/` (tmpfs)
6. Validator starts with decrypted keys
7. On shutdown, `ExecStopPost` runs cleanup script

### Step 4: Verify

```bash
# Check validator service status
ssh <vm-ip> 'sudo systemctl status validator'

# Check decryption logs
ssh <vm-ip> 'sudo journalctl -t validator-keys -f'

# Verify tmpfs mount
ssh <vm-ip> 'mountpoint /run/validator-keys'

# List decrypted keys (should see keystore files)
ssh <vm-ip> 'sudo ls -la /run/validator-keys/'
```

## Systemd Service Integration

### validator.service

```ini
[Service]
# KMS-encrypted key management
ExecStartPre=/usr/local/bin/decrypt-validator-keys.sh
ExecStopPost=/usr/local/bin/cleanup-validator-keys.sh

ExecStart=/usr/local/bin/nimbus_validator_client \
  --data-dir=/run/validator-keys \
  ...
```

**Key Points:**
- `ExecStartPre`: Runs BEFORE validator starts (decrypts keys)
- `ExecStopPost`: Runs AFTER validator stops (wipes keys)
- `--data-dir=/run/validator-keys`: Validator reads from tmpfs

## Troubleshooting

### Keys Not Decrypting

**Check GCS bucket:**
```bash
gcloud storage ls gs://eth-validator-bucket/validator-keys/encrypted/
```

**Check KMS permissions:**
```bash
gcloud kms keys get-iam-policy eth-validator \
  --keyring=eth-validator-val-keyring \
  --location=us-central1
```

**Check decryption logs:**
```bash
sudo journalctl -t validator-keys --since "10 minutes ago"
```

### Service Account Permissions

VM service account needs:
- `roles/cloudkms.cryptoKeyDecrypter` on KMS key
- `roles/storage.objectViewer` on GCS bucket

**Verify:**
```bash
# Get service account email
gcloud compute instances describe eth-validator-vm \
  --zone=us-central1-a \
  --format="value(serviceAccounts[0].email)"

# Check IAM bindings
gcloud projects get-iam-policy <project-id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:<sa-email>"
```

### tmpfs Not Mounted

```bash
# Check mount
mount | grep validator-keys

# Manually mount
sudo mount -t tmpfs -o size=100M,mode=0700 tmpfs /run/validator-keys
```

## Key Rotation

Cloud KMS automatically rotates encryption keys every 30 days. Existing encrypted keys remain accessible (KMS stores key versions).

**Manual rotation:**
```bash
# Re-encrypt keys with new KMS key version
./scripts/encrypt-and-upload-keys.sh

# Restart validator to use new keys
sudo systemctl restart validator
```

## Security Best Practices

1. **Delete Local Keys**: After encryption, securely delete original keystores from your local machine
   ```bash
   shred -vfz -n 10 validator_keys/keystore-*.json
   ```

2. **Backup Encrypted Keys**: GCS bucket has versioning enabled, but maintain offline backups

3. **Restrict KMS Access**: Only grant decrypt permission to validator VM service account

4. **Monitor Audit Logs**: Set up alerts for unexpected KMS access
   ```bash
   gcloud logging read "protoPayload.serviceName=cloudkms.googleapis.com" \
     --limit 50 --format json
   ```

5. **Rotate Regularly**: Even though KMS auto-rotates, consider re-encrypting keys annually

## Cost Considerations

**Cloud KMS:**
- Key versions: $0.06/month per active key version
- Operations: $0.03 per 10,000 decrypt operations
- Estimated monthly cost: ~$5-10

**Cloud Storage:**
- Storage: $0.020/GB/month (negligible for keystores)
- Operations: $0.004 per 10,000 operations
- Estimated monthly cost: <$1

**Total estimated cost: ~$10/month** for comprehensive key encryption

## References

- [Cloud KMS Documentation](https://cloud.google.com/kms/docs)
- [Ethereum Staking Launchpad](https://launchpad.ethereum.org/)
- [Nimbus Validator Keys](https://nimbus.guide/keys.html)
- [systemd ExecStartPre](https://www.freedesktop.org/software/systemd/man/systemd.service.html#ExecStartPre=)
