# Ansible Automation

Configuration management for Ethereum validator deployment using Ansible 2.14+.

## Structure

```
ansible/
├── ansible.cfg                          # Ansible configuration
├── inventory/
│   └── hosts.yml                        # Target hosts and variables
├── playbooks/
│   ├── deploy_validator.yml             # Main deployment playbook
│   ├── bootstrap_vm.yml                 # Fresh VM bootstrap
│   ├── start_services.yml               # Start validator services
│   ├── stop_services.yml                # Stop validator services
│   ├── restart_services.yml             # Graceful restart
│   ├── validate.yml                     # Health validation
│   ├── setup_kms_keys.yml               # KMS key infrastructure
│   ├── setup_deposit_cli.yml            # Validator key generation
│   └── upload_validator_keys.yml        # Encrypt and upload keys
├── roles/
│   ├── disk_setup/                      # Disk partitioning and mounting
│   ├── system_users/                    # User and group creation
│   ├── security_hardening/              # SSH, UFW, fail2ban
│   ├── jwt_secret/                      # JWT secret generation
│   ├── kms_secrets/                     # Cloud KMS integration
│   ├── nethermind/                      # Execution client
│   ├── nimbus/                          # Consensus + validator clients
│   └── validator_orchestration/         # Service startup orchestration
├── scripts/
│   ├── generate-ansible-inventory.sh    # Terraform output → Ansible inventory
│   └── upload-keystore-password.sh      # KMS-encrypt keystore passwords
└── vars/
    ├── common.yml                       # Common variables
    └── hoodi.yml                        # Hoodi testnet configuration
    └── holesky.yml                      # Holesky testnet configuration
```

## Quick Start

### Deploy Full Validator Stack
```bash
# From project root
sudo ./scripts/provision.sh

# Or directly with Ansible
cd ansible
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml
```

### Selective Deployment (Tags)
```bash
# Deploy only infrastructure setup
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml \
  --tags setup

# Deploy only Nethermind (execution client)
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml \
  --tags nethermind

# Deploy only Nimbus (consensus + validator)
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml \
  --tags nimbus

# Deploy only services configuration
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml \
  --tags services
```

## Inventory Configuration

### hosts.yml Structure
```yaml
all:
  children:
    eth_validator:
      hosts:
        eth_validator_vm:
          ansible_host: "{{ ansible_host }}"
          ansible_user: "{{ ansibler_user }}"
          ansible_ssh_private_key_file: ~/.ssh/id_rsa

  vars:
    # Testnet selection
    testnet_network: "hoodi"  # Options: hoodi, holesky

    # System requirements
    min_cpu_cores: 8
    min_memory_gb: 32
    min_disk_gb: 1000

    # Storage configuration
    disk_device: "/dev/sdb"
    mount_point: "/validator"

    # Fee recipient (IMPORTANT: Change this!)
    fee_recipient_address: "0x9AD0D357391e8XXXXXXXXXXXXXXXX"

    # Validator graffiti
    validator_graffiti: "Ethereum Validator"

    # GCP Configuration (for KMS integration)
    gcp_project_id: "<google_project_id>"
    gcp_region: "<google_region>"
    kms_keyring_name: "<kms_eth_keyring_name>"
    kms_key_name: "<kms_eth_name>"
    gcs_bucket_name: "<your_gcs_bucket_name>"
```

### Generating Inventory from Terraform
```bash
# Generate inventory/hosts.yml from Terraform outputs
./scripts/generate-ansible-inventory.sh

# Verify connectivity
ansible eth_validator -i inventory/hosts.yml -m ping
```

## Roles

### Infrastructure Roles

#### disk_setup
Partition and mount external disk for blockchain data.

**Variables:**
```yaml
disk_device: "/dev/sdb"
mount_point: "/validator"
```

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml --tags disk
```

#### system_users
Create non-root system users for each service.

**Created Users:**
```
execution:execution  → /validator/nethermind/
consensus:consensus  → /validator/nimbus/beacon/
validator:validator  → /validator/nimbus/validator/
```

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml --tags users
```

#### security_hardening
SSH hardening, firewall configuration, and security updates.

**Firewall Rules:**
```
Port   Protocol  Purpose
22     TCP       SSH
30303  TCP/UDP   Execution P2P
9000   TCP/UDP   Consensus P2P
```

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml --tags security
```

### Client Roles

#### nethermind
Execution client installation and configuration.

**Service Configuration:**
```ini
[Service]
User=execution
Group=execution
ExecStart=/usr/local/bin/nethermind \
  --config hoodi \
  --datadir /validator/nethermind \
  --JsonRpc.EnginePort 8551 \
  --JsonRpc.JwtSecretFile /validator/secrets/jwtsecret
```

**Ports:**
- 30303: P2P (TCP/UDP)
- 8545: JSON-RPC
- 8551: Engine API
- 9090: Metrics

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml --tags nethermind
```

#### nimbus
Consensus and validator client installation.

**Services:**
- consensus.service: Nimbus beacon node
- validator.service: Nimbus validator client

**Ports:**
- Beacon: 9000 (P2P), 5052 (REST API), 8008 (metrics)
- Validator: 8009 (metrics)

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml --tags nimbus
```

## Playbooks

### deploy_validator.yml
Main deployment playbook - full validator stack.

**Phases:**
1. Infrastructure: disk, users, security, JWT, KMS
2. Execution Layer: Nethermind
3. Consensus Layer: Nimbus beacon
4. Validator Layer: Nimbus validator
5. Orchestration: Service enablement

**Usage:**
```bash
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml
```

### Service Management Playbooks

```bash
# Start all services
ansible-playbook playbooks/start_services.yml -i inventory/hosts.yml

# Stop all services
ansible-playbook playbooks/stop_services.yml -i inventory/hosts.yml

# Graceful restart
ansible-playbook playbooks/restart_services.yml -i inventory/hosts.yml

# Health validation
ansible-playbook playbooks/validate.yml -i inventory/hosts.yml
```

## Tags Reference

| Tag | Description | Roles |
|-----|-------------|-------|
| `setup` | Infrastructure setup | disk_setup, system_users, security_hardening, jwt_secret, kms_secrets |
| `nethermind` | Execution client | nethermind |
| `nimbus` | Consensus + validator | nimbus |
| `services` | Service orchestration | validator_orchestration |

## Advanced Usage

### Parallel Execution
```bash
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml -f 5
```

### Dry Run
```bash
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml --check --diff
```

### Verbose Output
```bash
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml -vvv
```

### Override Variables
```bash
ansible-playbook playbooks/deploy_validator.yml -i inventory/hosts.yml \
  -e "fee_recipient_address=0xNewAddress"
```

## Troubleshooting

### Connectivity
```bash
# Test SSH
ansible eth_validator -i inventory/hosts.yml -m ping

# Check sudo
ansible eth_validator -i inventory/hosts.yml -a "whoami" -b
```

### Service Status
```bash
# Check services
ansible eth_validator -i inventory/hosts.yml -a "systemctl status execution consensus validator" -b

# View logs
ansible eth_validator -i inventory/hosts.yml -a "journalctl -u execution -n 50" -b
```

## Best Practices

1. Always use check mode first (`--check`)
2. Tag-based deployments for incremental updates
3. Version pin in production (avoid `latest`)
4. Backup before updates
5. Test in staging first
6. Use Ansible Vault for secrets
7. Keep playbooks idempotent
8. Document custom variables
9. Automate with CI/CD

For production enhancements, see [PRODUCTION.md](../docs/PRODUCTION.md).
