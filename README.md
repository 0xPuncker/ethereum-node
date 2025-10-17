# Ethereum Testnet Validator

<div align="center">
<p align="center">
  <img src="https://beincrypto.com/wp-content/uploads/2024/09/bic_EthereumPoW_ETHW_3-covers_neutral.jpg" alt="Ethereum Hoodi Testnet" width="350"/>
</p>

<div align="center">
  This repository is a one-click deployment solution for running a Ethereum node (testnet) on VM (GCP).

  > **Current Implementation:** Ansible-based deployment with Nethermind (execution) + Nimbus (consensus)
</div>

<br />
<div align="center">
  <!-- Docker -->
  <a href="https://www.docker.com/">
    <img src="https://img.shields.io/badge/Docker-v28+-blue" alt="Docker" />
  </a>
   <!-- Ansible -->
    <a href="https://www.ansible.com/">
      <img src="https://img.shields.io/badge/Ansible-v2.9+-blue" alt="Ansible" />
    </a>
    <!-- MIT License -->
    <a href="https://opensource.org/licenses/MIT">
      <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License" />
    </a>

</div>
<br />

## 📑 Table of Contents

- [Current Architecture](#️-current-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
  - [Command 1: Provision Infrastructure](#command-1-provision-infrastructure-️)
  - [Command 2: Start Validator](#command-2-start-validator-)
  - [Command 3: Check Health](#command-3-check-health-)
- [Monitoring and Management](#-monitoring-and-management)
  - [Service Logs](#service-logs)
  - [Sync Status Queries](#sync-status-queries)
  - [Metrics Endpoints](#metrics-endpoints)
- [Configuration](#-configuration)
  - [Inventory Configuration](#inventory-configuration)
  - [Testnet Selection](#testnet-selection)
- [Project Structure](#-project-structure)
- [Documentation](#-documentation)
- [Security & Key Management](#-security--key-management)
  - [KMS-Encrypted Validator Keys](#kms-encrypted-validator-keys-bonus-feature)
  - [General Security](#general-security)
- [License](#-license)
- [Acknowledgments](#-acknowledgments)
- [Support](#-support)

## 🏗️ Current Architecture

**Deployment:** GCP Compute Engine VM with Ansible automation

```
┌─────────────────────────────────────────────────────────────┐
│              GCP VM (Ubuntu 24.04 LTS)                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐     JWT Auth    ┌────────────────┐    │
│  │   Execution      │◄───────────────►│   Consensus    │    │
│  │   (Nethermind)   │   Engine API    │   (Nimbus)     │    │
│  │   Port 8551      │                 │   Beacon Node  │    │
│  │  • Blockchain DB │                 │                │    │
│  │  • P2P: 30303    │                 │  • P2P: 9000   │    │
│  │  • RPC: 8545     │                 │  • API: 5052   │    │
│  │  • Metrics: 9090 │                 │  • Metrics     │    │
│  └──────────────────┘                 └────────────────┘    │
│         │                                     │             │
│         └─────────────────┬───────────────────┘             │
│                           │                                 │
│                           ▼                                 │
│                  ┌─────────────────┐                        │
│                  │   Validator     │                        │
│                  │   (Nimbus)      │                        │
│                  │                 │                        │
│                  │  • Validator DB │                        │
│                  │  • Keys (enc.)  │                        │
│                  │  • Metrics:8009 │                        │
│                  └─────────────────┘                        │
│                                                             │
│  Storage: /validator (1TB persistent disk)                  │
│  ├─ /validator/nethermind/     (Execution data)             │
│  ├─ /validator/nimbus/          (Consensus data)            │
│  ├─ /validator/nimbus_validator/ (Validator keys)           │
│  └─ /validator/secrets/         (JWT secret)                │
│                                                             │
│  Services: systemd (execution, consensus, validator)        │
│  Security: SSH hardening, UFW firewall, non-root users       │
│  Network: Hoodi testnet (public Ethereum testnet)           │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

### Target System Requirements

- **OS**: Ubuntu 22.04/24.04 LTS
- **CPU**: 8+ cores
- **RAM**: 32GB+ (minimum for Testnet)
- **Disk**: 1TB+ SSD (persistent storage)
- **Network**: Stable connection, ports 22, 30303, 9000 open

### Control Machine Requirements

- **Ansible**: 2.14+ installed locally
- **SSH**: Key-based authentication to target VM
- **Git**: For cloning repository

## 🚀 Quick Start

**These are the ONLY 3 commands needed from a clean environment:**

### Command 1: Provision Infrastructure ⚙️

```bash
sudo ./scripts/provision.sh
```

**What it does:**

- Validates system requirements (CPU, RAM, disk, ports)
- Runs Ansible playbook to deploy full validator stack
- Sets up disk partitioning and mounting
- Creates system users (execution, consensus, validator)
- Configures SSH hardening and firewall
- Installs Nethermind (execution client)
- Installs Nimbus (consensus + validator clients)
- Configures JWT authentication between clients
- Generate validator keys and store it on KMS
- Creates systemd services for all components

**Duration:** ~10-30 minutes
**Output:** Infrastructure ready, services configured

---

### Command 2: Start Validator 🚀

```bash
sudo ./scripts/start-validator.sh
#NOTE: The *provision.sh* already start everything automatically.
```

**What it does:**

- Deploys Ethereum validator stack via Ansible
- Starts execution.service (Nethermind)
- Starts consensus.service (Nimbus beacon)
- Waits for execution layer to be responsive
- Initializes consensus client with checkpoint sync
- Verifies all services are running

**Duration:** ~2-3 minutes
**Output:** All services running, beginning sync to Hoodi testnet

---

### Command 3: Check Health ✅

```bash
./scripts/check-health.sh
```

**What it does:**

- Queries execution client RPC (port 8545)
- Queries consensus client REST API (port 5052)
- Displays sync status (syncing vs synced)
- Shows peer connections
- Shows serivices status
- Reports validator status (if keys imported)
- Displays resource usage (disk, memory)
- Returns exit code 0 (healthy) or 1 (unhealthy)

**Example Output:**

```

```

**Duration:** ~5-10 seconds
**Output:** Human-readable health status

## 📊 Monitoring and Management

### Service Logs

```bash
# View execution client logs
ssh <vm-ip> 'sudo journalctl -fu execution'

# View consensus client logs
ssh <vm-ip> 'sudo journalctl -fu consensus'

# View validator client logs
ssh <vm-ip> 'sudo journalctl -fu validator'
```

### Sync Status Queries

```bash
# Execution sync status (via RPC)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://<vm-ip>:8545

# Consensus sync status (via REST API)
curl http://<vm-ip>:5052/eth/v1/node/syncing | jq

# Peer counts
curl http://<vm-ip>:5052/eth/v1/node/peer_count | jq
```

### Metrics Endpoints

- **Nethermind**: `http://<vm-ip>:9090/metrics` (Prometheus format)
- **Nimbus Beacon**: `http://<vm-ip>:8008/metrics` (Prometheus format)
- **Nimbus Validator**: `http://<vm-ip>:8009/metrics` (Prometheus format)

## 🔧 Configuration

### Inventory Configuration

Edit `ansible/inventory/hosts.yml` to customize:

```yaml
all:
  children:
    validator_nodes:
      hosts:
        eth-validator-vm:
          ansible_host: <YOUR_VM_IP> # Change this
          ansible_user: <YOUR_USERNAME> # Change this

  vars:
    # Testnet selection
    testnet_network: "hoodi" # or "holesky"

    # Fee recipient (CHANGE THIS!)
    fee_recipient_address: "0xYourEthereumAddress"

    # Client versions (auto-download latest)
    nethermind_version: "latest"
    nimbus_version: "latest"

    # System requirements
    min_cpu_cores: 4
    min_memory_gb: 30
    min_disk_gb: 500
```

### Testnet Selection

- **Hoodi** (default): Recommended, stable, active validator set
- **Holesky**: Alternative testnet, smaller validator set

Change in `ansible/vars/common.yml` or inventory

## 📝 Project Structure

```ethereum-node/
├── scripts/
│   ├── provision.sh                # Command 1: Infrastructure setup
│   ├── start-validator.sh          # Command 2: Start validator
│   └── check-health.sh             # Command 3: Health check
│
├── ansible/                        # Ansible automation
│   ├── playbooks/
│   │   ├── deploy_validator.yml        # Main deployment playbook
│   │   ├── preflight.yml                # System validation
│   │   └── validate.yml                # Post-deployment checks
│   ├── secure/                         # Save mnemonic and validator files
│   ├── roles/
│   │   ├── disk_setup/                 # Disk partitioning
│   │   ├── system_users/               # User creation
│   │   ├── security_hardening/         # SSH + firewall
│   │   ├── jwt_secret/                 # JWT generation
│   │   ├── nethermind/                 # Execution client
│   │   ├── nimbus/                     # Consensus + validator
│   │   └── validator_orchestration/    # Service startup
│   ├── inventory/
│   │   └── hosts.yml                   # Target hosts config
│   └── vars/
│       └── common.yml                  # Common node variables
│       └── holesky.yml                 # Testnet holesky variables
│       └── hoodi.yml                   # Testnet hoodi variables
│
├── terraform/                 # GCP infrastructure (optional)
│   ├── main.tf                # VM provisioning
│   ├── modules/               # Reusable modules
│   └── variables.tf           # Configuration
│
└── docs/                      # Documentation
    ├── CHALLENGE.MD           # Original challenge
    ├── TODO.md                # Implementation checklist
    └── ARCHITECTURE.md        # Design details
```

## 📖 Documentation

- [Architecture](docs/ARCHITECTURE.md) - System architecture and design decisions
- [KMS Key Management](docs/KMS_KEY_MANAGEMENT.md) - KMS keys and management
- [Ansible Guide](ansible/README.md) - Detailed Ansible automation guide
- [Hoodi Validator Registration](docs/HOODI_VALIDATOR_REGISTRATION.md) - Detailed Hoodi validator registration
- [Runbook](docs/RUNBOOK.md) - Runbook

## 🔐 Security & Key Management

### KMS-Encrypted Validator Keys (Bonus Feature)

**Production-grade key encryption** using Google Cloud KMS ensures validator private keys are never stored in plaintext:

```
Key Lifecycle:
1. Generate keys locally (EthStaker deposit-cli)
2. Encrypt with Cloud KMS → ./ansible/scripts/encrypt-and-upload-keys.sh
3. Store encrypted in GCS bucket
4. On validator start: decrypt to tmpfs (memory-only)
5. On validator stop: securely wipe from memory
```

**Security Features:**

- 🔒 **AES-256 Encryption** - Industry-standard Cloud KMS encryption
- 🔄 **Automatic Key Rotation** - 30-day rotation policy
- 💾 **Memory-Only Storage** - Decrypted keys never touch disk (tmpfs)
- 🧹 **Secure Deletion** - Keys wiped with shred on service stop
- 📋 **Audit Logging** - All KMS operations logged to Cloud Logging
- 🔑 **IAM Access Control** - Minimal permissions (decrypt only)

**Quick Start:**

```bash
# 1. Encrypt local validator keystores
./scripts/encrypt-and-upload-keys.sh

# 2. Deploy validator (keys auto-decrypted on start)
sudo ./scripts/start-validator.sh

# 3. Verify key decryption
ssh <vm-ip> 'sudo journalctl -t validator-keys -f'
```

**Documentation:**

- [KMS Key Management Guide](docs/KMS_KEY_MANAGEMENT.md)

## 📄 License

[MIT](https://choosealicense.com/licenses/mit/)

## 🙏 Acknowledgments

- [Ethereum Foundation](https://ethereum.org/)
- [Hoodi Ethereum Explorer](https://hoodi.beaconcha.in/)
- [Validator Cheklist](https://hoodi.launchpad.ethstaker.cc/en/checklist)
- [Becoming a Hoodi Validator](https://hoodi.launchpad.ethstaker.cc/en/overview)
- [Hoodi Faucet](https://hoodi-faucet.pk910.de/)
- [Validator's List](https://hoodi.beaconcha.in/validators#all)

## 💬 Support

For support, please open an issue on the GitHub repository.
