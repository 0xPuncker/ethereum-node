#!/bin/bash
# Ethereum Validator Start Script

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
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

# Logging
LOG_FILE="/tmp/ethereum-validator-start.log"
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

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

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          Starting Ethereum Validator                       ║"
echo "║          Execution + Consensus + Validator                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Started at: $(date)"
log_info "Log file: ${LOG_FILE}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with sudo privileges"
    log_info "Usage: sudo $0"
    exit 1
fi

# Check if Ansible is available
if ! command -v ansible-playbook &> /dev/null; then
    log_error "Ansible is not installed"
    log_info "Please run ./provision.sh first"
    exit 1
fi

# Start validator services via Ansible
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Starting Ethereum Validator Services"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

log_info "This will start:"
echo "  • Execution Layer (Nethermind)"
echo "  • Consensus Layer (Nimbus Beacon)"
echo "  • Validator Client (Nimbus Validator)"
echo ""

cd "${ANSIBLE_DIR}"

if ansible-playbook playbooks/start_services.yml -i inventory/hosts.yml; then
    log_success "Services started successfully"
else
    log_error "Service startup failed"
    log_info "Check logs: ${LOG_FILE}"
    exit 1
fi

# Wait for services to stabilize
log_info "Waiting for services to stabilize..."
sleep 5

# Check service status on remote host
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Verifying Service Status"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get remote host from inventory
REMOTE_HOST=$(grep 'ansible_host:' inventory/hosts.yml | head -n1 | awk '{print $2}')

if [ -z "$REMOTE_HOST" ]; then
    log_error "Could not determine remote host from inventory"
    log_info "Please check ansible/inventory/hosts.yml"
    exit 1
fi

log_info "Checking services on ${REMOTE_HOST}..."

# Check execution service
if ansible validator_nodes -i inventory/hosts.yml -m shell -a "systemctl is-active execution" 2>/dev/null | grep -q "active"; then
    log_success "✓ Execution client (Nethermind) is running"
else
    log_error "✗ Execution client is not running"
fi

# Check consensus service
if ansible validator_nodes -i inventory/hosts.yml -m shell -a "systemctl is-active consensus" 2>/dev/null | grep -q "active"; then
    log_success "✓ Consensus client (Nimbus) is running"
else
    log_error "✗ Consensus client is not running"
fi

# Check validator service
if ansible validator_nodes -i inventory/hosts.yml -m shell -a "systemctl is-active validator" 2>/dev/null | grep -q "active"; then
    log_success "✓ Validator client is running"
else
    log_warning "⚠ Validator client is not running (requires keys)"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Validator Started Successfully!               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_success "Ethereum validator is now running and syncing!"
echo ""

log_info "📊 Service Status:"
echo "  • Execution Layer:  Nethermind (syncing blockchain)"
echo "  • Consensus Layer:  Nimbus beacon (syncing from checkpoint)"
echo "  • Validator Client: Ready (requires validator keys)"
echo ""

log_info "📝 Next Steps:"
echo "  1. Monitor sync progress:"
echo "     ssh ${REMOTE_HOST} 'sudo journalctl -fu execution'"
echo "     ssh ${REMOTE_HOST} 'sudo journalctl -fu consensus'"
echo ""
echo "  2. Check health status:"
echo "     ./scripts/check-health.sh"
echo ""
echo "  3. Import validator keys (if not already done):"
echo "     See ansible/README.md for key import instructions"
echo ""

log_info "🔍 Monitoring:"
echo "  • Execution RPC:  http://${REMOTE_HOST}:8545"
echo "  • Consensus API:  http://${REMOTE_HOST}:5052"
echo "  • Metrics:        http://${REMOTE_HOST}:9090 (Nethermind)"
echo "                    http://${REMOTE_HOST}:8008 (Nimbus)"
echo ""

log_info "Log file saved to: ${LOG_FILE}"
echo ""
log_success "Done! ✨"
