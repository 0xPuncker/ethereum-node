# Documentation Index

Technical documentation for Ethereum validator deployment on GCP.

## Architecture & Design

### [ARCHITECTURE.md](ARCHITECTURE.md)

**System architecture and infrastructure flow**

Complete infrastructure diagram from control machine through Terraform/Ansible to deployed services. Covers component communication, security model, key encryption workflow, deployment stages, network architecture, and design decisions.

**Key Topics:**

- Infrastructure flow: Terraform → GCP → Ansible → Services → Monitoring
- Component communication: Execution ↔ Consensus ↔ Validator
- Security model: User isolation, KMS encryption, tmpfs storage
- Network architecture: VPC, firewall rules, P2P connectivity
- Deployment stages and performance characteristics

---

## Production & Operations

### [PRODUCTION.md](PRODUCTION.md)

**Production-ready improvements and migration guide**

Comprehensive guide for migrating from Ansible deployment to production Kubernetes setup. Includes containerization, GitOps, CI/CD, observability, multi-region deployment, HA configuration, and disaster recovery.

**Key Topics:**

- Dockerfiles for Nethermind, Nimbus beacon, validator
- Kubernetes StatefulSets with PVC and health probes
- Helm charts for deployment management
- ArgoCD GitOps with sync waves
- GitHub Actions CI/CD pipeline
- Prometheus + Grafana + Loki observability stack
- Multi-region deployment and HA setup
- Velero disaster recovery
- Cost optimization strategies

---

## Infrastructure as Code

### [../terraform/README.md](../terraform/README.md)

**GCP infrastructure provisioning**

Terraform/OpenTofu modules for GCP infrastructure: VM instances, networking, Cloud KMS, GCS buckets, IAM. Includes variable reference, outputs, cost estimation, state management, and Ansible integration.

**Modules:**

- **compute**: VM instance, service account, persistent disks
- **network**: VPC, subnet, firewall rules
- **kms**: Cloud KMS keyring and crypto key for encryption
- **storage**: GCS bucket with CMEK encryption
- **loadbalancer**: HTTP(S) load balancer (optional)

**Cost:** ~$358/month (us-central1)

---

## Configuration Management

### [../ansible/README.md](../ansible/README.md)

**Ansible automation and roles**

Ansible playbooks and roles for validator deployment. Covers infrastructure setup, client installation, service orchestration, and operational playbooks.

**Roles:**

- **disk_setup**: Partition and mount /validator disk
- **system_users**: Create execution, consensus, validator users
- **security_hardening**: SSH, UFW, fail2ban
- **nethermind**: Execution client installation
- **nimbus**: Consensus + validator installation
- **validator_orchestration**: Service startup coordination

**Playbooks:**

- deploy_validator.yml - Full validator stack
- start_services.yml - Start all services
- stop_services.yml - Stop all services
- validate.yml - Health validation

---

## Operational Scripts

### [../scripts/README.md](../scripts/README.md)

**Deployment and management scripts**

Operational scripts for validator deployment, service management, and health monitoring.

**Scripts:**

- **provision.sh**: Infrastructure provisioning (~10-15 min)
- **start-validator.sh**: Start validator services (~2-3 min)
- **check-health.sh**: Health check and status reporting (~5-10 sec)
- **gcp-preflight.sh**: GCP environment validation (~10-20 sec)

**Workflows:**

1. Provision infrastructure
2. Start validator services
3. Check health status
4. Monitor logs (journalctl)

---

## Troubleshooting & Operations

### Common Issues

**Service Failures:**

```bash
# Check systemd status
sudo systemctl status execution consensus validator

# View logs
sudo journalctl -fu execution
sudo journalctl -fu consensus
sudo journalctl -fu validator
```

**Sync Status:**

```bash
# Execution client RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545

# Consensus client REST API
curl http://localhost:5052/eth/v1/node/syncing | jq
```

**GCP Issues:**

```bash
# Check VM access
gcloud compute ssh eth-validator-vm --zone=us-central1-a

# Check firewall rules
gcloud compute firewall-rules list --filter="name~'eth-validator'"

# Verify KMS key access
gcloud kms keys describe eth-validator \
  --location=us-central1 \
  --keyring=eth-validator-val-keyring
```

---

## Quick Reference

### System Requirements

- **OS**: Ubuntu 22.04/24.04 LTS
- **CPU**: 8+ cores
- **RAM**: 30GB+ (minimum for Holesky)
- **Disk**: 1TB+ SSD (persistent storage)
- **Network**: Ports 22, 30303, 9000 open

### Service Ports

```
Execution (Nethermind):
  30303 - P2P (TCP/UDP)
  8545  - JSON-RPC
  8551  - Engine API (JWT auth)
  9090  - Metrics

Consensus (Nimbus Beacon):
  9000  - P2P (TCP/UDP)
  5052  - REST API
  8008  - Metrics

Validator (Nimbus Validator):
  8009  - Metrics
```

### Key Paths

```
Data:
  /validator/nethermind/     - Execution data
  /validator/nimbus/          - Consensus data
  /validator/nimbus_validator/ - Validator keys

Secrets:
  /validator/secrets/jwtsecret - JWT token

Logs:
  journalctl -u execution
  journalctl -u consensus
  journalctl -u validator
```

---

## External Resources

- [Ethereum Staking Launchpad](https://launchpad.ethereum.org/) - Official validator onboarding
- [Nethermind Docs](https://docs.nethermind.io/) - Execution client documentation
- [Nimbus Book](https://nimbus.guide/) - Consensus/validator client documentation
- [CoinCashew Guides](https://www.coincashew.com/) - Community staking guides
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest) - GCP resource reference
- [Ansible Documentation](https://docs.ansible.com/) - Automation framework

---

## Contributing

When updating documentation:

1. **Follow existing patterns** - Keep consistent structure and tone
2. **Be technical** - Focus on operational details, not explanations
3. **Include commands** - Show actual commands and configurations
4. **Add examples** - Provide working examples with expected output
5. **Update cross-references** - Keep links between docs synchronized
6. **Test procedures** - Verify commands work before documenting

For questions or issues, see [GitHub Issues](https://github.com/0xPuncker/ethereum-node/issues).
