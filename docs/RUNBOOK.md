# Ethereum Validator - Technical Runbook

**Version:** 1.0
**Last Updated:** 2025-10-17
**Environment:** Google Cloud Platform
**Network:** Hoodi Testnet (configurable)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Infrastructure Management](#4-infrastructure-management)
5. [Service Deployment](#5-service-deployment)
6. [Operational Procedures](#6-operational-procedures)
7. [Monitoring & Health Checks](#7-monitoring--health-checks)
8. [Troubleshooting](#8-troubleshooting)
9. [Emergency Procedures](#9-emergency-procedures)
10. [Maintenance Tasks](#10-maintenance-tasks)
11. [Security Operations](#11-security-operations)

---

## 1. System Overview

### 1.1 Purpose

Production-grade Ethereum validator infrastructure running on Google Cloud Platform with enterprise-level security, automated configuration management, and comprehensive monitoring.

### 1.2 Components

#### Infrastructure Layer (Terraform/OpenTofu)

- **Compute Engine VM**: Ubuntu-based validator node
- **VPC Network**: Isolated private network with custom subnet (10.20.0.0/24)
- **Cloud KMS**: Customer-managed encryption keys (CMEK) for disk/secret encryption
- **Cloud Storage**: Encrypted bucket for validator key backups
- **Load Balancer**: HTTP(S) load balancer with health checks
- **Static IP**: Reserved external IP for stable connectivity

#### Application Layer (Ansible)

- **Execution Client**: Nethermind (Ethereum execution layer)
- **Consensus Client**: Nimbus Beacon (Ethereum consensus layer)
- **Validator Client**: Nimbus Validator (attestation & block proposal)
- **Supporting Services**: JWT authentication, KMS key decryption, system hardening

### 1.3 System Requirements

| Component   | Minimum          | Recommended      |
| ----------- | ---------------- | ---------------- |
| **CPU**     | 4 cores          | 8+ cores         |
| **RAM**     | 30 GB            | 32+ GB           |
| **Disk**    | 500 GB SSD       | 1+ TB NVMe SSD   |
| **Network** | 10 Mbps          | 25+ Mbps         |
| **OS**      | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

### 1.4 Network Ports

| Service           | Port  | Protocol | Purpose                   |
| ----------------- | ----- | -------- | ------------------------- |
| **SSH**           | 22    | TCP      | Remote administration     |
| **Execution P2P** | 30303 | TCP/UDP  | Nethermind peer discovery |
| **Consensus P2P** | 9000  | TCP/UDP  | Nimbus peer discovery     |
| **Execution RPC** | 8545  | TCP      | JSON-RPC API (localhost)  |
| **Consensus API** | 5052  | TCP      | Beacon API (localhost)    |
| **JWT Auth**      | 8551  | TCP      | Engine API (localhost)    |

---

## 2. Architecture

### 2.1 Infrastructure Topology

```
┌─────────────────────────────────────────────────────────────┐
│                     Google Cloud Platform                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              VPC Network (eth-validator-vpc)         │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │   Subnet: 10.20.0.0/24 (us-central1)           │  │   │
│  │  │                                                │  │   │
│  │  │   ┌─────────────────────────────────────────┐  │  │   │
│  │  │   │   Compute Instance (eth-validator-vm)   │  │  │   │
│  │  │   │   ┌─────────────────────────────────┐   │  │  │   │
│  │  │   │   │  Nethermind (Execution)        │    │  │  │   │
│  │  │   │   │  :8545 (RPC) :30303 (P2P)      │    │  │  │   │
│  │  │   │   └─────────────────────────────────┘   │  │  │   │
│  │  │   │   ┌─────────────────────────────────┐   │  │  │   │
│  │  │   │   │  Nimbus Beacon (Consensus)     │    │  │  │   │
│  │  │   │   │  :5052 (API) :9000 (P2P)       │    │  │  │   │
│  │  │   │   └─────────────────────────────────┘   │  │  │   │
│  │  │   │   ┌─────────────────────────────────┐   │  │  │   │
│  │  │   │   │  Nimbus Validator              │    │  │  │   │
│  │  │   │   │  (Attestations & Proposals)    │    │  │  │   │
│  │  │   │   └─────────────────────────────────┘   │  │  │   │
│  │  │   │                                         │  │  │   │
│  │  │   │   Persistent Disk (KMS Encrypted)       │  │  │   │
│  │  │   │   /dev/sdb → /validator (1TB+)          │  │  │   │
│  │  │   └─────────────────────────────────────────┘  │  │   │
│  │  │                                                │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │                                                      │   │
│  │  Firewall Rules:                                     │   │
│  │  - SSH: Your IP/32 → :22                             │   │
│  │  - P2P: 0.0.0.0/0 → :30303, :9000                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Cloud KMS (eth-validator-keyring)            │   │
│  │  - Crypto Key: eth-validator                         │   │
│  │  - Rotation: 30 days                                 │   │
│  │  - Used for: Disk encryption, secret encryption      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │      Cloud Storage (eth-validator-bucket)            │   │
│  │  - KMS-encrypted validator key backups               │   │
│  │  - Keystore passwords (encrypted)                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │      Load Balancer (eth-validator-lb)                │   │
│  │  - Health checks for VM availability                 │   │
│  │  - Static external IP                                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Service Dependencies

```
Startup Order:
1. Disk mounted (/dev/sdb → /validator)
2. System users created (execution, consensus, validator)
3. JWT secret generated
4. KMS secrets decrypted
5. Nethermind (execution) started
6. Nimbus Beacon (consensus) started ← depends on execution
7. Nimbus Validator started ← depends on consensus + keys

Runtime Dependencies:
- Validator → Consensus API (:5052)
- Consensus → Execution Engine API (:8551 via JWT)
- Execution → Ethereum P2P Network
- Consensus → Ethereum Beacon Network
```

### 2.3 Data Storage Layout

```
/validator/                             # Persistent disk mount
├── nethermind/                         # Execution client data
│   ├── chainspec/
│   ├── Data/                           # Blockchain data
│   └── logs/
├── nimbus/
│   └── beacon/                         # Consensus client data
│       ├── db/                         # Beacon chain database
│       └── network_metadata/
├── nimbus_validator/                   # Validator client data
│   └── validators/
└── secrets/
    ├── jwtsecret                       # JWT for engine API auth
    └── kms_cache/                      # Decrypted KMS secrets

/run/validator-keys/                    # tmpfs (memory)
    ├── keystore-*.json                 # Decrypted keystores (RAM only)
    └── passwords.txt                   # Keystore passwords (RAM only)
```

---

## 3. Prerequisites

### 3.1 Required Tools

**Local Machine:**

```bash
# Infrastructure
terraform >= 1.0 (or opentofu >= 1.6)
ansible >= 2.14
task >= 3.0

# GCP CLI
gcloud >= 400.0
```

**Installation:**

```bash
# Taskfile (task runner)
brew install go-task  # macOS
# or
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d

# OpenTofu
brew install opentofu  # macOS
# or
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | sh

# Ansible
pip3 install ansible
```

### 3.2 GCP Authentication

```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Set project
export GCP_PROJECT="your-project-id"
gcloud config set project $GCP_PROJECT

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

### 3.3 SSH Configuration

```bash
# Generate SSH key (if needed)
ssh-keygen -t ed25519 -C "eth-validator" -f ~/.ssh/id_ed25519

# Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### 3.4 Project Configuration

```bash
# Create terraform.tfvars
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit required variables:
# - project_id
# - resource_prefix
# - machine_type
# - ansible_user
# - ssh_public_key_file
```

---

## 4. Infrastructure Management

### 4.1 Initial Deployment

**Complete infrastructure provisioning:**

```bash
# Full deployment pipeline
task validator:deploy:all

# This executes:
# 1. Terraform init/plan/apply (infrastructure)
# 2. Generate Ansible inventory
# 3. Bootstrap VM (security, users, disk)
# 4. Deploy validator services
# 5. Generate & upload validator keys
# 6. Validate deployment
```

**Step-by-step deployment:**

```bash
# Step 1: Provision infrastructure
task validator:deploy:infra
# → tofu init, plan, apply

# Step 2: Bootstrap VM
task validator:deploy:bootstrap
# → generate inventory, run bootstrap playbook

# Step 3: Deploy services
task validator:deploy:services
# → install Nethermind, Nimbus, configure systemd

# Step 4: Setup validator keys
task validator:deploy:keys
# → generate keys, encrypt, upload, restart validator

# Step 5: Validate
task validator:deploy:finalize
# → run health checks
```

### 4.2 Terraform Operations

**Basic commands:**

```bash
# Initialize Terraform
task tf:init

# Plan changes
task tf:plan

# Apply changes
task tf:apply

# Show outputs
task tf:output

# Destroy infrastructure (CAUTION)
task tf:destroy
```

**Retrieve infrastructure info:**

```bash
# Get VM external IP
cd terraform && tofu output -raw vm_external_ip

# Get all outputs
task tf:output
```

**Import existing KMS resources:**

```bash
# If KMS keyring already exists
cd terraform
tofu import 'module.kms.google_kms_key_ring.this[0]' \
  projects/PROJECT_ID/locations/REGION/keyRings/KEYRING_NAME

tofu import 'module.kms.google_kms_crypto_key.this[0]' \
  projects/PROJECT_ID/locations/REGION/keyRings/KEYRING_NAME/cryptoKeys/KEY_NAME
```

> Tip: When you want to reference existing resources without importing them, set `kms_create_key_ring = false` and/or `kms_create_crypto_key = false` and Terraform will read the metadata instead of creating those resources.

### 4.3 State Management

**Backend configuration:**

```hcl
# terraform/backend.tf (recommended for production)
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "ethereum-validator/state"
  }
}
```

**State operations:**

```bash
# Show state
cd terraform && tofu state list

# Inspect resource
tofu state show 'module.compute.google_compute_instance.vm'

# Refresh state
tofu refresh
```

---

## 5. Service Deployment

### 5.1 Ansible Inventory

**Generate from Terraform:**

```bash
task ansible:inventory:generate
```

**Manual configuration:**

```yaml
# ansible/inventory/hosts.yml
all:
  children:
    eth-validator:
      hosts:
        eth-validator-vm:
          ansible_host: <VM_EXTERNAL_IP>
          ansible_user: <SSH_USER>
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519

  vars:
    testnet_network: "hoodi" # or "holesky"
    fee_recipient_address: "0xYourEthereumAddress"
    validator_graffiti: "YourGraffiti"
```

**Validate inventory:**

```bash
# Show inventory
task ansible:inventory:show

# Test connectivity
task ansible:inventory:ping
```

### 5.2 Bootstrap New VM

**First-time VM setup:**

```bash
# Dry-run (check mode)
task ansible:bootstrap-check

# Execute bootstrap
task ansible:bootstrap
```

**Bootstrap playbook includes:**

- Disk setup and mounting (/dev/sdb → /validator)
- System user creation (execution, consensus, validator)
- Security hardening (SSH, firewall, fail2ban)
- Essential package installation
- NTP time synchronization

### 5.3 Deploy Validator Services

**Full deployment:**

```bash
# Check mode (dry-run)
task ansible:deploy-check

# Execute deployment
task ansible:deploy

# Verbose mode (debugging)
task ansible:deploy-verbose
```

**Deployment phases:**

1. **Infrastructure Preparation**

   - Disk setup
   - User creation
   - Security hardening
   - JWT secret generation
   - KMS secret decryption

2. **Execution Layer (Nethermind)**

   - Download and install binary
   - Configure for testnet
   - Create systemd service
   - Start execution client

3. **Consensus Layer (Nimbus)**

   - Download and install binary
   - Configure beacon node
   - Configure validator client
   - Create systemd services
   - Start consensus and validator

4. **Service Orchestration**
   - Enable services on boot
   - Verify startup order
   - Apply health checks

### 5.4 Tag-Based Deployment

**Deploy specific components:**

```bash
# Setup only (disk, users, security)
task ansible:deploy-tags -- TAG=setup

# Execution client only
task ansible:deploy-tags -- TAG=nethermind

# Consensus client only
task ansible:deploy-tags -- TAG=nimbus

# Services configuration only
task ansible:deploy-tags -- TAG=services
```

**Available tags:**

- `setup`, `infrastructure` - Base system configuration
- `disk` - Disk mounting and formatting
- `users` - System user creation
- `security` - Security hardening
- `jwt` - JWT secret generation
- `kms` - KMS key decryption
- `nethermind`, `execution` - Execution client
- `nimbus`, `consensus`, `validator` - Consensus/validator clients
- `services`, `orchestration` - Service management

---

## 6. Operational Procedures

### 6.1 Service Management

**Start services:**

```bash
# Start all services
task validator:start

# Or use Ansible directly
task ansible:start
```

**Stop services:**

```bash
# Stop all services (graceful shutdown)
task validator:stop

# Or use Ansible
task ansible:stop
```

**Restart services:**

```bash
# Graceful restart with health checks
task validator:restart

# Or use Ansible
task ansible:restart
```

**Service status:**

```bash
# SSH into VM
task vm:ssh

# Check service status
sudo systemctl status execution
sudo systemctl status consensus
sudo systemctl status validator

# Check all validator services
sudo systemctl status execution consensus validator
```

### 6.2 Log Management

**Stream logs (from local machine):**

```bash
# Execution client logs
task validator:logs-execution

# Consensus client logs
task validator:logs-consensus

# Validator client logs
task validator:logs

# All services combined
task validator:logs-all

# Search for errors (last hour)
task validator:logs-error
```

**View logs (on VM):**

```bash
# SSH into VM
task vm:ssh

# Live logs
sudo journalctl -fu execution
sudo journalctl -fu consensus
sudo journalctl -fu validator

# Combined logs
sudo journalctl -u execution -u consensus -u validator -f

# Logs with color
sudo journalctl -fu execution | ccze
sudo journalctl -fu consensus | ccze

# Historical logs
sudo journalctl -u execution --since "1 hour ago"
sudo journalctl -u consensus --since "2 hours ago" --until "1 hour ago"

# Export logs
sudo journalctl -u execution --since today > execution-$(date +%Y%m%d).log
```

**KMS key decryption logs:**

```bash
# From local machine
task vm:logs:kms

# On VM
sudo journalctl -t validator-keys -f
```

### 6.3 Configuration Updates

**Update validator configuration:**

```bash
# Modify ansible/inventory/hosts.yml
# Change: fee_recipient_address, validator_graffiti, etc.

# Apply changes
task ansible:update-validator
```

**Update network configuration:**

```bash
# Switch testnet network
# Edit ansible/inventory/hosts.yml
testnet_network: "holesky"  # or "hoodi"

# Redeploy services
task ansible:deploy
```

### 6.4 Validator Key Management

**Generate new validator keys:**

```bash
# Complete key workflow
task validator:deploy:keys

# This executes:
# 1. Install staking-deposit-cli
# 2. Generate mnemonic & keystores
# 3. Encrypt with KMS
# 4. Upload to GCS bucket
# 5. Decrypt on VM to tmpfs
# 6. Reload validator service
```

**Manual key operations:**

```bash
# Install deposit-cli only
task ansible:staking-deposit

# Upload existing keys
task ansible:upload-keys

# Upload keystore passwords
task ansible:upload-passwords
```

**Verify keys loaded:**

```bash
task vm:ssh
sudo ls -lah /run/validator-keys/
# Should show keystore-*.json files
```

### 6.5 SSH Access

**Connect to validator VM:**

```bash
# Using task
task vm:ssh

# Direct SSH
ssh $(cd terraform && tofu output -raw ansible_user)@$(cd terraform && tofu output -raw vm_external_ip)
```

---

## 7. Monitoring & Health Checks

### 7.1 Automated Health Checks

**Run comprehensive health check:**

```bash
# From local machine
./scripts/check-health.sh

# Or via Ansible validation
task ansible:validate
```

**Health check components:**

1. **System Services**

   - Execution, consensus, validator service status

2. **Execution Layer Status**

   - Sync state (syncing/synced)
   - Current block number
   - Peer count
   - Sync progress percentage

3. **Consensus Layer Status**

   - Sync state
   - Current slot/epoch
   - Finalized epoch
   - Peer count
   - Sync distance

4. **Validator Status** (if keys loaded)

   - Validator public keys
   - On-chain status (active/pending/exited)
   - Balance (ETH)
   - Effective balance
   - Next attestation slot

5. **Resource Usage**
   - Disk usage
   - Memory usage

**Health states:**

- **HEALTHY** (exit 0): All services synced, validator attesting
- **SYNCING** (exit 0): Services syncing, normal for new deployments
- **UNHEALTHY** (exit 1): Critical services down, requires action

### 7.2 Manual Health Checks

**Execution client (Nethermind):**

```bash
# Check sync status
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545

# Get current block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545

# Get peer count
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545
```

**Consensus client (Nimbus):**

```bash
# Check sync status
curl http://127.0.0.1:5052/eth/v1/node/syncing

# Get node health
curl http://127.0.0.1:5052/eth/v1/node/health

# Get peer count
curl http://127.0.0.1:5052/eth/v1/node/peer_count

# Get current header
curl http://127.0.0.1:5052/eth/v1/beacon/headers/head

# Get finality checkpoints
curl http://127.0.0.1:5052/eth/v1/beacon/states/head/finality_checkpoints
```

**Validator status:**

```bash
# Get validator by pubkey
PUBKEY="0xYourValidatorPubkey"
curl http://127.0.0.1:5052/eth/v1/beacon/states/head/validators/$PUBKEY

# Get validator by index
VALIDATOR_INDEX="123456"
curl http://127.0.0.1:5052/eth/v1/beacon/states/head/validators/$VALIDATOR_INDEX
```

### 7.3 Performance Metrics

**System resources:**

```bash
# CPU usage
top -bn1 | grep "Cpu(s)"

# Memory usage
free -h

# Disk usage
df -h /validator

# Network I/O
ifstat 1 5

# Service resource usage
systemctl status execution | grep -A 2 "Memory"
systemctl status consensus | grep -A 2 "Memory"
```

**Blockchain sync progress:**

```bash
# Execution client logs
sudo journalctl -u execution --since "5 minutes ago" | grep -i "sync\|block"

# Consensus client logs
sudo journalctl -u consensus --since "5 minutes ago" | grep -i "sync\|slot\|finalized"
```

### 7.4 Alerting & Notifications

**Key metrics to monitor:**

| Metric                 | Warning Threshold    | Critical Threshold    |
| ---------------------- | -------------------- | --------------------- |
| Execution sync lag     | > 10 blocks          | > 50 blocks           |
| Consensus sync lag     | > 32 slots (1 epoch) | > 64 slots (2 epochs) |
| Peer count (execution) | < 5 peers            | < 3 peers             |
| Peer count (consensus) | < 20 peers           | < 10 peers            |
| Disk usage             | > 80%                | > 90%                 |
| Memory usage           | > 85%                | > 95%                 |
| Missed attestations    | > 1 per epoch        | > 3 per epoch         |
| Service downtime       | > 30 seconds         | > 2 minutes           |

**Monitoring setup (recommended):**

```bash
# Install node_exporter for Prometheus
sudo apt-get install prometheus-node-exporter

# Install Grafana Cloud agent (for remote monitoring)
# https://grafana.com/docs/grafana-cloud/monitor-infrastructure/integrations/

# Use GCP Cloud Monitoring
# Enable VM monitoring in GCP console
```

---

## 8. Troubleshooting

### 8.1 Common Issues

#### Services Not Starting

**Symptom:** Service fails to start or crashes immediately

**Diagnosis:**

```bash
# Check service status
sudo systemctl status execution
sudo systemctl status consensus
sudo systemctl status validator

# View recent logs
sudo journalctl -u execution -n 100 --no-pager
sudo journalctl -u consensus -n 100 --no-pager
sudo journalctl -u validator -n 100 --no-pager

# Check for port conflicts
sudo netstat -tlnp | grep -E "8545|8551|5052|30303|9000"
```

**Common causes:**

- **Missing dependencies:** JWT secret not generated
- **Permission issues:** Data directory ownership incorrect
- **Port conflicts:** Another service using required ports
- **Corrupted database:** Database files corrupted

**Resolution:**

```bash
# Fix data directory permissions
sudo chown -R execution:execution /validator/nethermind
sudo chown -R consensus:consensus /validator/nimbus
sudo chown -R validator:validator /validator/nimbus_validator

# Regenerate JWT secret
sudo rm -f /validator/secrets/jwtsecret
task ansible:deploy-tags -- TAG=jwt

# Kill conflicting processes
sudo lsof -ti:8545 | xargs sudo kill -9

# Reset database (CAUTION: requires resync)
sudo systemctl stop execution
sudo rm -rf /validator/nethermind/Data/
sudo systemctl start execution
```

#### Sync Issues

**Symptom:** Client stuck syncing or sync progress very slow

**Diagnosis:**

```bash
# Execution client sync
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq

# Consensus client sync
curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq

# Check peer connections
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq

curl -s http://127.0.0.1:5052/eth/v1/node/peer_count | jq
```

**Common causes:**

- **Network issues:** Firewall blocking P2P ports
- **No peers:** Unable to discover or connect to peers
- **Checkpoint sync failed:** Consensus client checkpoint sync issue
- **Disk I/O bottleneck:** Slow disk causing sync delays

**Resolution:**

```bash
# Verify firewall rules
sudo ufw status
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp
sudo ufw allow 9000/tcp
sudo ufw allow 9000/udp

# Check GCP firewall
gcloud compute firewall-rules list --filter="targetTags:eth-validator"

# Restart with different checkpoint
# Edit ansible/inventory/hosts.yml
checkpoint_sync_url: "https://hoodi.beaconstate.ethstaker.cc"
task ansible:deploy-tags -- TAG=nimbus
task validator:restart

# Monitor disk I/O
iostat -x 5
```

#### Validator Not Attesting

**Symptom:** Validator not performing duties, missing attestations

**Diagnosis:**

```bash
# Check validator service
sudo systemctl status validator
sudo journalctl -u validator -n 50 --no-pager

# Verify keys loaded
sudo ls -lah /run/validator-keys/

# Check validator status on-chain
PUBKEY=$(sudo jq -r '.pubkey' /run/validator-keys/keystore-*.json | head -1)
curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/validators/0x$PUBKEY | jq
```

**Common causes:**

- **Keys not loaded:** Validator keys not in /run/validator-keys/
- **Consensus not synced:** Beacon node still syncing
- **Validator not activated:** Deposit not confirmed or in activation queue
- **Fee recipient invalid:** Invalid Ethereum address for fee recipient

**Resolution:**

```bash
# Reload validator keys
task validator:deploy:keys

# Verify consensus sync
curl -s http://127.0.0.1:5052/eth/v1/node/syncing | jq .data.is_syncing

# Check deposit status on explorer
# https://hoodi.beaconcha.in/validator/<pubkey>

# Update fee recipient
# Edit ansible/inventory/hosts.yml
fee_recipient_address: "0xYourValidAddress"
task ansible:update-validator
task validator:restart
```

#### KMS Decryption Failures

**Symptom:** Validator keys not decrypted to tmpfs

**Diagnosis:**

```bash
# Check KMS logs
sudo journalctl -t validator-keys -n 50 --no-pager

# Verify service account permissions
gcloud projects get-iam-policy $(gcloud config get-value project) \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:*eth-validator-sa*"

# List encrypted keys in GCS bucket
gsutil ls gs://$(cd terraform && tofu output -raw bucket_name)/validator-keys/
```

**Common causes:**

- **IAM permissions missing:** Service account lacks KMS permissions
- **KMS key unavailable:** KMS key disabled or deleted
- **Network issues:** Cannot reach KMS or GCS APIs
- **Encrypted keys missing:** Keys not uploaded to GCS

**Resolution:**

```bash
# Grant KMS permissions to service account
SA_EMAIL=$(cd terraform && tofu output -raw service_account_email)
KMS_KEY=$(cd terraform && tofu output -raw kms_crypto_key_id)

gcloud kms keys add-iam-policy-binding \
  --project=$(gcloud config get-value project) \
  --location=us-central1 \
  --keyring=eth-validator-keyring \
  --member="serviceAccount:$SA_EMAIL" \
  --role=roles/cloudkms.cryptoKeyEncrypterDecrypter \
  eth-validator

# Re-upload validator keys
task ansible:upload-keys
task ansible:upload-passwords

# Manually trigger KMS setup
task ansible:kms-setup

# Restart services
task validator:restart
```

### 8.2 Performance Issues

#### High Memory Usage

**Diagnosis:**

```bash
# System memory
free -h
ps aux --sort=-%mem | head -10

# Service memory
systemctl status execution | grep Memory
systemctl status consensus | grep Memory
```

**Resolution:**

```bash
# Adjust Java heap for Nethermind (if needed)
# Edit nethermind service file
sudo systemctl edit execution
# Add:
[Service]
Environment="DOTNET_GCHeapHardLimit=0x800000000"  # 32GB max

sudo systemctl daemon-reload
sudo systemctl restart execution

# For consensus client, reduce cache size
# Edit nimbus service configuration via ansible role
```

#### High Disk Usage

**Diagnosis:**

```bash
# Disk usage by directory
sudo du -h --max-depth=2 /validator/

# Largest files
sudo find /validator -type f -size +1G -exec ls -lh {} \;

# Disk I/O
iostat -x 5 3
```

**Resolution:**

```bash
# Prune execution client (if supported)
# Nethermind auto-prunes by default

# Rotate logs
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=5G

# Expand disk (if needed)
# 1. Resize disk in GCP console or Terraform
# 2. Expand partition on VM
sudo growpart /dev/sdb 1
sudo resize2fs /dev/sdb1
```

### 8.3 Network Issues

#### Peer Connection Problems

**Diagnosis:**

```bash
# Check peer count
curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545 | jq -r .result | xargs printf "%d\n"

curl -s http://127.0.0.1:5052/eth/v1/node/peer_count | jq .data.connected

# Test external connectivity
nc -zv 1.1.1.1 443
nc -zv 8.8.8.8 53

# Check firewall
sudo ufw status verbose
```

**Resolution:**

```bash
# Verify GCP firewall rules
gcloud compute firewall-rules list --format="table(name,allowed,sourceRanges,targetTags)"

# Add missing P2P rules
gcloud compute firewall-rules create eth-validator-p2p \
  --network=eth-validator-vpc \
  --allow=tcp:30303,udp:30303,tcp:9000,udp:9000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=eth-validator

# Restart networking
sudo systemctl restart systemd-networkd
```

### 8.4 Log Analysis

**Search for errors:**

```bash
# Execution errors (last 1 hour)
sudo journalctl -u execution --since "1 hour ago" | grep -i "error\|fatal\|panic"

# Consensus errors
sudo journalctl -u consensus --since "1 hour ago" | grep -i "error\|fatal\|warn"

# Validator errors
sudo journalctl -u validator --since "1 hour ago" | grep -i "error\|failed\|missed"
```

**Export logs for analysis:**

```bash
# Export to file
sudo journalctl -u execution --since today > /tmp/execution-$(date +%Y%m%d).log
sudo journalctl -u consensus --since today > /tmp/consensus-$(date +%Y%m%d).log

# Download from VM
scp $(cd terraform && tofu output -raw ansible_user)@$(cd terraform && tofu output -raw vm_external_ip):/tmp/*.log ./logs/
```

---

## 9. Emergency Procedures

### 9.1 Service Recovery

**Emergency service restart:**

```bash
# Immediate restart (no confirmation)
task vm:ssh
sudo systemctl restart execution consensus validator

# From local machine
ssh $(cd terraform && tofu output -raw ansible_user)@$(cd terraform && tofu output -raw vm_external_ip) \
  'sudo systemctl restart execution consensus validator'
```

**Service crash loop recovery:**

```bash
# Disable auto-restart temporarily
sudo systemctl stop execution
sudo systemctl disable execution

# Fix underlying issue (check logs)
sudo journalctl -u execution -n 200 --no-pager

# Re-enable and start
sudo systemctl enable execution
sudo systemctl start execution
```

### 9.2 Data Corruption

**Execution client database corruption:**

```bash
# CAUTION: Requires full resync (2-4 hours)

# Stop service
sudo systemctl stop execution

# Backup corrupted DB
sudo mv /validator/nethermind/Data /validator/nethermind/Data.corrupted.$(date +%Y%m%d)

# Start fresh sync
sudo systemctl start execution

# Monitor progress
sudo journalctl -u execution -f
```

**Consensus client database corruption:**

```bash
# CAUTION: Requires resync (15-30 minutes with checkpoint)

# Stop services
sudo systemctl stop validator consensus

# Backup corrupted DB
sudo mv /validator/nimbus/beacon/db /validator/nimbus/beacon/db.corrupted.$(date +%Y%m%d)

# Start fresh sync with checkpoint
sudo systemctl start consensus

# Wait for consensus sync, then start validator
sleep 300
sudo systemctl start validator
```

### 9.3 Validator Key Recovery

**Restore keys from backup:**

```bash
# Keys are in GCS bucket (KMS-encrypted)
BUCKET=$(cd terraform && tofu output -raw bucket_name)
gsutil ls gs://$BUCKET/validator-keys/

# Download encrypted keys
gsutil cp gs://$BUCKET/validator-keys/* /tmp/

# Re-run KMS setup to decrypt
task ansible:kms-setup

# Restart validator
task validator:restart
```

**Import keys from mnemonic:**

```bash
# SSH into VM
task vm:ssh

# Install deposit-cli (if not installed)
# Run key generation
cd ~/staking-deposit-cli
./deposit generate-keys \
  --chain=hoodi \
  --mnemonic="your 24 word mnemonic here" \
  --validator_start_index=0 \
  --num_validators=1

# Upload generated keys
# Exit VM and run:
task ansible:upload-keys
task ansible:upload-passwords
```

### 9.4 Emergency Shutdown

**Graceful shutdown (planned maintenance):**

```bash
# Stop validator first (avoid slashing)
task vm:ssh
sudo systemctl stop validator
sleep 30

# Stop consensus
sudo systemctl stop consensus
sleep 10

# Stop execution
sudo systemctl stop execution

# Verify all stopped
sudo systemctl status execution consensus validator
```

**Force shutdown (emergency):**

```bash
# From GCP console or CLI
gcloud compute instances stop eth-validator-vm \
  --zone=us-central1-a
```

### 9.5 Disaster Recovery

**Complete infrastructure rebuild:**

```bash
# 1. Ensure validator keys backed up in GCS
BUCKET=$(cd terraform && tofu output -raw bucket_name)
gsutil ls gs://$BUCKET/validator-keys/

# 2. Destroy existing infrastructure
task tf:destroy

# 3. Redeploy from scratch
task validator:deploy:all

# 4. Keys will be automatically restored from GCS
```

**Recover from snapshot (recommended setup):**

```bash
# Create disk snapshot (run regularly)
gcloud compute disks snapshot eth-validator-vm-data \
  --zone=us-central1-a \
  --snapshot-names=eth-validator-backup-$(date +%Y%m%d)

# Restore from snapshot
gcloud compute disks create eth-validator-vm-data-restored \
  --source-snapshot=eth-validator-backup-YYYYMMDD \
  --zone=us-central1-a

# Update Terraform to use restored disk
# terraform/modules/compute/main.tf
# Replace google_compute_disk.data with existing disk reference
```

---

## 10. Maintenance Tasks

### 10.1 Regular Maintenance

**Daily checks:**

```bash
# Health check
./scripts/check-health.sh

# Check for errors
task validator:logs-error

# Verify attestations
# Check validator dashboard: https://hoodi.beaconcha.in/
```

**Weekly tasks:**

```bash
# Update system packages (during low-activity period)
task vm:ssh
sudo apt-get update
sudo apt-get upgrade -y

# Review disk usage
df -h /validator
sudo du -h --max-depth=1 /validator/ | sort -h

# Check service logs for warnings
sudo journalctl -u execution --since "7 days ago" | grep -i "warn" | wc -l
sudo journalctl -u consensus --since "7 days ago" | grep -i "warn" | wc -l

# Verify backups in GCS
gsutil ls gs://$(cd terraform && tofu output -raw bucket_name)/validator-keys/
```

**Monthly tasks:**

```bash
# Review and rotate logs
sudo journalctl --vacuum-time=30d
sudo journalctl --verify

# Update client versions (if available)
# Check releases:
# - Nethermind: https://github.com/NethermindEth/nethermind/releases
# - Nimbus: https://github.com/status-im/nimbus-eth2/releases

# Update ansible/vars/common.yml versions
# nethermind_version: "1.x.x"
# nimbus_version: "v24.x.x"
task ansible:deploy-tags -- TAG=nethermind
task ansible:deploy-tags -- TAG=nimbus
task validator:restart

# Terraform state refresh
cd terraform && tofu refresh

# Review GCP costs
gcloud billing accounts list
```

### 10.2 Client Updates

**Update execution client (Nethermind):**

```bash
# 1. Check current version
task vm:ssh
/usr/local/bin/nethermind --version

# 2. Update version in ansible/vars/common.yml
nethermind_version: "1.XX.X"

# 3. Deploy update
task ansible:deploy-tags -- TAG=nethermind

# 4. Restart service
sudo systemctl restart execution

# 5. Verify version
/usr/local/bin/nethermind --version
sudo journalctl -u execution -f
```

**Update consensus/validator client (Nimbus):**

```bash
# 1. Check current version
task vm:ssh
/usr/local/bin/nimbus_beacon_node --version
/usr/local/bin/nimbus_validator_client --version

# 2. Update version in ansible/vars/common.yml
nimbus_version: "v24.X.X"

# 3. Deploy update
task ansible:deploy-tags -- TAG=nimbus

# 4. Restart services (validator first for graceful)
sudo systemctl restart validator
sleep 10
sudo systemctl restart consensus

# 5. Verify versions
/usr/local/bin/nimbus_beacon_node --version
sudo journalctl -u consensus -f
```

**Rollback procedure (if update fails):**

```bash
# 1. Stop services
sudo systemctl stop validator consensus execution

# 2. Revert ansible version
# Edit ansible/vars/common.yml back to previous version

# 3. Redeploy old version
task ansible:deploy-tags -- TAG=nethermind
task ansible:deploy-tags -- TAG=nimbus

# 4. Start services
sudo systemctl start execution
sleep 60
sudo systemctl start consensus
sleep 30
sudo systemctl start validator
```

### 10.3 Backup Procedures

**Backup validator keys (automated):**

```bash
# Keys automatically backed up to GCS during deployment
task validator:deploy:keys

# Manual backup verification
BUCKET=$(cd terraform && tofu output -raw bucket_name)
gsutil ls -lh gs://$BUCKET/validator-keys/
```

**Backup configuration:**

```bash
# Backup Ansible configuration
tar -czf ansible-config-$(date +%Y%m%d).tar.gz ansible/

# Backup Terraform state
cd terraform
tofu state pull > terraform.tfstate.backup.$(date +%Y%m%d)

# Store offsite
# Upload to secure location (e.g., another GCS bucket, S3, local encrypted drive)
```

**Create disk snapshot:**

```bash
# Create snapshot
gcloud compute disks snapshot eth-validator-vm-data \
  --zone=us-central1-a \
  --snapshot-names=eth-validator-data-$(date +%Y%m%d-%H%M) \
  --description="Ethereum validator data backup"

# List snapshots
gcloud compute snapshots list --filter="name~'eth-validator'"

# Set retention policy (optional)
gcloud compute snapshots add-labels eth-validator-data-YYYYMMDD \
  --labels=retention=30days
```

### 10.4 Disk Expansion

**Expand persistent disk:**

```bash
# 1. Resize disk in Terraform
# terraform/variables.tf or terraform.tfvars
data_disk = {
  type = "pd-ssd"
  size = 1000  # Increase from 500 to 1000GB
}

# 2. Apply Terraform changes
task tf:apply

# 3. SSH into VM and expand filesystem
task vm:ssh
sudo growpart /dev/sdb 1
sudo resize2fs /dev/sdb1

# 4. Verify new size
df -h /validator
```

### 10.5 Security Patching

**Apply security updates:**

```bash
# SSH into VM
task vm:ssh

# Check for security updates
sudo apt-get update
sudo apt-get upgrade -s | grep -i security

# Apply security updates (minimal disruption)
sudo apt-get install --only-upgrade $(apt-get -s upgrade | grep -i security | awk '{print $2}')

# Reboot if kernel updated (plan during low-activity)
sudo reboot
```

**Update SSH configuration:**

```bash
# Review SSH security
task vm:ssh
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication"

# Update via Ansible
# Edit ansible/inventory/hosts.yml or ansible/vars/common.yml
# Redeploy security role
task ansible:deploy-tags -- TAG=security
```

---

## 11. Security Operations

### 11.1 Access Management

**Add new SSH key:**

```bash
# Add to Terraform variables
# terraform/variables.tf
ssh_public_key_file = "~/.ssh/new_key_ed25519.pub"

# Apply changes
task tf:apply

# Or add via GCP console
gcloud compute instances add-metadata eth-validator-vm \
  --metadata-from-file ssh-keys=new_authorized_keys.txt \
  --zone=us-central1-a
```

**Revoke SSH access:**

```bash
# Remove from metadata
gcloud compute instances remove-metadata eth-validator-vm \
  --keys=ssh-keys \
  --zone=us-central1-a

# Re-add only authorized keys
gcloud compute instances add-metadata eth-validator-vm \
  --metadata-from-file ssh-keys=authorized_keys.txt \
  --zone=us-central1-a
```

### 11.2 Firewall Management

**Review firewall rules:**

```bash
# List GCP firewall rules
gcloud compute firewall-rules list \
  --filter="network:eth-validator-vpc" \
  --format="table(name,allowed,sourceRanges,targetTags)"

# Check UFW on VM
task vm:ssh
sudo ufw status verbose
```

**Restrict SSH access:**

```bash
# Update Terraform to restrict SSH
# terraform/main.tf (local variables)
locals {
  ssh_public_cidr = ["YOUR_NEW_IP/32"]  # Update this
}

# Apply changes
task tf:apply

# Verify
gcloud compute firewall-rules describe eth-validator-vpc-ssh
```

**Emergency firewall lockdown:**

```bash
# Block all inbound except SSH from your IP
gcloud compute firewall-rules update eth-validator-vpc-allow \
  --disabled

# Create temporary SSH-only rule
gcloud compute firewall-rules create eth-validator-emergency-ssh \
  --network=eth-validator-vpc \
  --allow=tcp:22 \
  --source-ranges=YOUR_IP/32 \
  --target-tags=eth-validator \
  --priority=100
```

### 11.3 Secret Rotation

**Rotate JWT secret:**

```bash
# SSH into VM
task vm:ssh
sudo systemctl stop validator consensus execution

# Generate new JWT secret
sudo openssl rand -hex 32 > /validator/secrets/jwtsecret.new
sudo mv /validator/secrets/jwtsecret.new /validator/secrets/jwtsecret
sudo chown root:root /validator/secrets/jwtsecret
sudo chmod 640 /validator/secrets/jwtsecret

# Update service configurations (if needed)
# Restart services
sudo systemctl start execution
sleep 60
sudo systemctl start consensus
sleep 30
sudo systemctl start validator
```

**Rotate KMS key:**

```bash
# GCP KMS handles automatic rotation
# Verify rotation period
gcloud kms keys describe eth-validator \
  --keyring=eth-validator-keyring \
  --location=us-central1 \
  --format="value(rotationPeriod)"

# Manual rotation (creates new version)
gcloud kms keys versions create \
  --key=eth-validator \
  --keyring=eth-validator-keyring \
  --location=us-central1 \
  --primary
```

### 11.4 Audit Logging

**Enable GCP audit logs:**

```bash
# Enable data access logs
gcloud logging write --severity=INFO audit-test "Enabling audit logs"

# View recent audit events
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=eth-validator-vm" \
  --limit=50 \
  --format=json
```

**Review SSH access logs:**

```bash
task vm:ssh
sudo grep -i "Accepted\|Failed" /var/log/auth.log | tail -50
```

**Service account activity:**

```bash
# List service account keys
gcloud iam service-accounts keys list \
  --iam-account=$(cd terraform && tofu output -raw service_account_email)

# Review service account activity
gcloud logging read "protoPayload.authenticationInfo.principalEmail=$(cd terraform && tofu output -raw service_account_email)" \
  --limit=20 \
  --format=json
```

### 11.5 Incident Response

**Security incident checklist:**

1. **Isolate:**

   ```bash
   # Disable all firewall rules
   gcloud compute firewall-rules list --format="value(name)" \
     --filter="network:eth-validator-vpc" | \
     xargs -I {} gcloud compute firewall-rules update {} --disabled
   ```

2. **Assess:**

   ```bash
   # Check running processes
   task vm:ssh
   ps aux

   # Check network connections
   sudo netstat -tulpn

   # Review recent commands
   history
   sudo cat /home/*/.bash_history
   ```

3. **Preserve evidence:**

   ```bash
   # Create disk snapshot
   gcloud compute disks snapshot eth-validator-vm-data \
     --zone=us-central1-a \
     --snapshot-names=incident-$(date +%Y%m%d-%H%M%S)

   # Export logs
   gcloud logging read "resource.type=gce_instance" \
     --format=json > incident-logs-$(date +%Y%m%d).json
   ```

4. **Contain:**

   ```bash
   # Stop compromised services
   sudo systemctl stop validator consensus execution

   # Or shutdown VM entirely
   gcloud compute instances stop eth-validator-vm --zone=us-central1-a
   ```

5. **Remediate:**

   - Review and apply security patches
   - Rotate all credentials (SSH keys, service account keys)
   - Rebuild from clean state if necessary
   - Update firewall rules

6. **Recover:**

   ```bash
   # Restore from snapshot or rebuild
   task validator:deploy:all
   ```

7. **Review:**
   - Document incident timeline
   - Identify root cause
   - Update runbook and automation
   - Implement preventive controls

---

## Appendix

### A. Service Specifications

**Execution Client (Nethermind)**

- **Binary:** `/usr/local/bin/nethermind`
- **Data:** `/validator/nethermind`
- **Service:** `execution.service`
- **User:** `execution`
- **Ports:** 8545 (RPC), 8551 (Engine), 30303 (P2P)

**Consensus Client (Nimbus Beacon)**

- **Binary:** `/usr/local/bin/nimbus_beacon_node`
- **Data:** `/validator/nimbus/beacon`
- **Service:** `consensus.service`
- **User:** `consensus`
- **Ports:** 5052 (API), 9000 (P2P)

**Validator Client (Nimbus Validator)**

- **Binary:** `/usr/local/bin/nimbus_validator_client`
- **Data:** `/validator/nimbus_validator`
- **Service:** `validator.service`
- **User:** `validator`
- **Keys:** `/run/validator-keys` (tmpfs)

### B. Directory Structure

```
/validator/                        # Persistent disk mount
├── nethermind/                    # Execution client
│   ├── chainspec/
│   ├── Data/
│   │   ├── state/
│   │   └── receipts/
│   └── logs/
├── nimbus/
│   └── beacon/                    # Consensus client
│       ├── db/
│       └── network_metadata/
├── nimbus_data/                   # Validator client
│   └── validators/
└── secrets/
    ├── jwtsecret                  # JWT for engine API
    └── kms_cache/                 # KMS metadata

/run/validator-keys/               # tmpfs (RAM-only)
    ├── keystore-*.json            # Decrypted keystores
    └── passwords.txt              # Keystore passwords

/etc/systemd/system/
    ├── execution.service
    ├── consensus.service
    └── validator.service

/usr/local/bin/
    ├── nethermind
    ├── nimbus_beacon_node
    └── nimbus_validator_client
```

### C. Environment Variables

**Ansible Inventory Variables:**

- `testnet_network`: Network name (hoodi/holesky)
- `fee_recipient_address`: ETH address for block rewards
- `validator_graffiti`: Custom validator graffiti
- `checkpoint_sync_url`: Checkpoint sync endpoint
- `execution_p2p_port`: Execution P2P port (30303)
- `consensus_p2p_port`: Consensus P2P port (9000)

**Terraform Variables:**

- `project_id`: GCP project ID
- `region`: GCP region (us-central1)
- `zone`: GCP zone (us-central1-a)
- `resource_prefix`: Resource naming prefix
- `machine_type`: VM instance type
- `ansible_user`: SSH user for Ansible

### D. Quick Reference Commands

**Task Commands:**

```bash
# Infrastructure
task tf:init tf:plan tf:apply tf:output

# Deployment
task validator:deploy:all
task ansible:deploy

# Service control
task validator:start
task validator:stop
task validator:restart

# Monitoring
task validator:logs-execution
task validator:logs-consensus
task validator:logs
./scripts/check-health.sh

# Maintenance
task ansible:update-validator
task validator:deploy:keys
task vm:ssh
```

**Health Check URLs:**

```bash
# Execution
http://127.0.0.1:8545 (JSON-RPC)

# Consensus
http://127.0.0.1:5052/eth/v1/node/health
http://127.0.0.1:5052/eth/v1/node/syncing
http://127.0.0.1:5052/eth/v1/node/peer_count

# Explorer
https://hoodi.beaconcha.in
```

### E. Useful Resources

**Official Documentation:**

- Nethermind: https://docs.nethermind.io/
- Nimbus: https://nimbus.guide/
- Ethereum: https://ethereum.org/en/developers/docs/

**Network Resources:**

- Hoodi Testnet: https://hoodi.launchpad.ethereum.org/
- Holesky Testnet: https://holesky.launchpad.ethereum.org/
- Checkpoint Sync: https://hoodi.beaconstate.ethstaker.cc

**Tools:**

- Beaconcha.in Explorer: https://hoodi.beaconcha.in
- EthStaker Community: https://ethstaker.cc/
- Deposit CLI: https://github.com/ethereum/staking-deposit-cli

---

**END OF RUNBOOK**

_For questions or issues, consult the troubleshooting section or reach out to the infrastructure team._
