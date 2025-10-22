#!/bin/bash
# Ethereum Validator Health Check Script
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

truncate_pubkey() {
    local key="$1"
    key="${key//$''\r/}"
    key="${key//$''\n/}"
    key="${key// /}"

    if [[ -z "$key" ]]; then
        echo ""
        return
    fi

    local display_key="${key}"
    if [[ "${display_key:0:2}" == "0x" || "${display_key:0:2}" == "0X" ]]; then
        display_key="${display_key:2}"
    fi

    local length=${#display_key}
    if (( length <= 14 )); then
        echo "0x${display_key}"
    else
        echo "0x${display_key:0:8}...${display_key: -6}"
    fi
}

ensure_hex_key() {
    local key="$1"
    key="${key//$''\r/}"
    key="${key//$''\n/}"
    key="${key// /}"
    if [[ -z "$key" ]]; then
        echo ""
        return
    fi

    key=$(printf '%s' "$key" | tr 'A-F' 'a-f')

    if [[ "${key:0:2}" == "0x" || "${key:0:2}" == "0X" ]]; then
        echo "0x${key:2}"
    else
        echo "0x${key}"
    fi
}

# Banner
echo "============================================================"
echo "__________ __  .__                                        "
echo "\_   _____//  |_|  |__   ___________   ____  __ __  _____  "
echo " |    __)_\   __\  |  \_/__ \_  __ \_/ __ \|  |  \/     \ "
echo " |        \|  | |   Y  \  ___/|  | \/  ___/|  |  /  Y Y  / "
echo "/_______  /|__| |___|  /\___  >__|    \___  >____/|__|_|  / "
echo "        \/           \/     \/            \/            \/ "
echo "____   ____      .__  .__    .___       __                 "
echo "\   \ /   /____  |  | |__| __| _/____ _/  |_  ___________ "
echo " \   Y   /\__  \ |  | |  |/ __ |\__  \\   __\/  _ \_  __ \ "
echo "  \     /  / __ \|  |_|  / /_/ | / __ \|  | (  <_> )  | \/ "
echo "   \___/  (____  /____/__\____ |(____  /__|  \____/|__|    "
echo "               \/             \/     \/                    "
echo "============================================================"
echo ""
log_info "Script: Validator Health Check"
log_info "$(date)"

if ! command -v ansible &> /dev/null; then
    log_error "Ansible is not installed"
    log_info "Please run ./provision.sh first"
    exit 1
fi

if [ -f "${PROJECT_ROOT}/.envrc" ]; then
    source "${PROJECT_ROOT}/.envrc"
fi

if [ -n "${VM_EXTERNAL_IP:-}" ]; then
    REMOTE_HOST="$VM_EXTERNAL_IP"
else
    cd "${ANSIBLE_DIR}"
    REMOTE_HOST=$(grep -E '^[[:space:]]*ansible_host:[[:space:]]*' inventory/hosts.yml 2>/dev/null | head -n1 | awk '{print $2}' | tr -d '"' || echo "")

    if [ -z "$REMOTE_HOST" ]; then
        log_error "Could not determine remote host"
        log_info "Please ensure VM_EXTERNAL_IP is set in .envrc or run terraform first"
        exit 1
    fi
fi

cd "${ANSIBLE_DIR}"
log_info "Server: ${REMOTE_HOST}"
echo ""

# 0 = healthy, 1 = degraded, 2 = unhealthy
OVERALL_HEALTH=0

print_header "━━━ System Services ━━━"
echo ""

check_service() {
    local service_name=$1
    local display_name=$2

    if ansible validator -i inventory/hosts.yml -m shell -a "systemctl is-active ${service_name}" 2>/dev/null | grep -q "active"; then
        log_success "${display_name} is running"
        return 0
    else
        log_error "${display_name} is not running"
        OVERALL_HEALTH=2
        return 1
    fi
}

check_service "execution" "Execution Layer (Nethermind)"
check_service "consensus" "Consensus Layer (Nimbus Beacon)"

if check_service "validator" "Validator Client (Nimbus Validator)"; then
    VALIDATOR_RUNNING=true
else
    VALIDATOR_RUNNING=false
    log_warning "Validator not running (keys may not be imported)"
    if [ $OVERALL_HEALTH -lt 1 ]; then
        OVERALL_HEALTH=1
    fi
fi

echo ""

# Check 2: Execution Layer Status
print_header "━━━ Execution Layer Status ━━━"
echo ""

# Check if execution client is syncing
EXEC_SYNC_RESPONSE=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://127.0.0.1:8545" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")

if [ -z "$EXEC_SYNC_RESPONSE" ] || echo "$EXEC_SYNC_RESPONSE" | grep -q "error\|timed out\|refused"; then
    log_error "Cannot connect to execution client RPC"
    log_info "  Ensure execution service is running and port 8545 is open"
    OVERALL_HEALTH=2
else
    EXEC_SYNC=$(echo "$EXEC_SYNC_RESPONSE" | sed -n 's/.*"result":\([^,}]*\).*/\1/p')

    if [ "$EXEC_SYNC" = "false" ]; then
        log_success "Execution client is fully synced"

        # Get current block number
        BLOCK_NUMBER=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://127.0.0.1:8545" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="result"){print $(i+2)}}}' || echo "0x0")
        BLOCK_DEC=$((16#${BLOCK_NUMBER#0x}))
        log_info "  Current block: ${BLOCK_DEC}"
    else
        log_warning "Execution client is syncing..."
        OVERALL_HEALTH=1

        # Show sync progress if available
        CURRENT_BLOCK=$(echo "$EXEC_SYNC_RESPONSE" | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="currentBlock"){print $(i+2)}}}')
        HIGHEST_BLOCK=$(echo "$EXEC_SYNC_RESPONSE" | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="highestBlock"){print $(i+2)}}}')

        if [ -n "$CURRENT_BLOCK" ] && [ -n "$HIGHEST_BLOCK" ]; then
            CURRENT_DEC=$((16#${CURRENT_BLOCK#0x}))
            HIGHEST_DEC=$((16#${HIGHEST_BLOCK#0x}))

            if [ $HIGHEST_DEC -gt 0 ]; then
                SYNC_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($CURRENT_DEC / $HIGHEST_DEC) * 100}")
                log_info "  Sync progress: ${SYNC_PERCENT}% (${CURRENT_DEC}/${HIGHEST_DEC})"
            fi
        fi
    fi
fi

EXEC_PEERS=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' http://127.0.0.1:8545" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="result"){print $(i+2)}}}' || echo "0x0")

PEER_COUNT=$((16#${EXEC_PEERS#0x}))
if [ $PEER_COUNT -gt 0 ]; then
    log_success "Connected to ${PEER_COUNT} execution peers"
else
    log_warning "No execution peers connected"
    OVERALL_HEALTH=1
fi

echo ""

print_header "━━━ Consensus Layer Status ━━━"
echo ""

CONSENSUS_SYNC_RESPONSE=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s http://127.0.0.1:5052/eth/v1/node/syncing" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")

if [ -z "$CONSENSUS_SYNC_RESPONSE" ] || echo "$CONSENSUS_SYNC_RESPONSE" | grep -q "error\|timed out\|refused"; then
    log_error "Cannot connect to consensus client API"
    log_info "  Ensure consensus service is running and port 5052 is open"
    OVERALL_HEALTH=2
else
    CONSENSUS_SYNC=$(echo "$CONSENSUS_SYNC_RESPONSE" | awk -F':' '{for(i=1;i<=NF;i++){if($i~/"is_syncing"/){print $(i+1)}}}' | tr -d ',' | tr -d ' ')
    HEAD_RESPONSE=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s http://127.0.0.1:5052/eth/v1/beacon/headers/head" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")
    CURRENT_SLOT=$(echo "$HEAD_RESPONSE" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="slot"){print $(i+2)}}}')
    # Assuming 32 slots per epoch
    CURRENT_EPOCH=$((CURRENT_SLOT / 32))
    FINALITY_RESPONSE=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/finality_checkpoints" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")
    FINALIZED_EPOCH=$(echo "$FINALITY_RESPONSE" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="epoch"){print $(i+2)}}}' | head -1)

    if [ "$CONSENSUS_SYNC" = "false" ]; then
        log_success "Consensus client is fully synced"

        if [ -n "$CURRENT_SLOT" ]; then
            log_info "  Current slot: ${CURRENT_SLOT} (epoch ${CURRENT_EPOCH})"
        fi

        if [ -n "$FINALIZED_EPOCH" ]; then
            log_info "  Finalized epoch: ${FINALIZED_EPOCH}"
        fi
    else
        log_warning "Consensus client is syncing..."
        OVERALL_HEALTH=1
        HEAD_SLOT=$(echo "$CONSENSUS_SYNC_RESPONSE" | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="head_slot"){print $(i+2)}}}')
        SYNC_DISTANCE=$(echo "$CONSENSUS_SYNC_RESPONSE" | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="sync_distance"){print $(i+2)}}}')

        if [ -n "$HEAD_SLOT" ] && [ -n "$SYNC_DISTANCE" ] && [ "$SYNC_DISTANCE" != "0" ]; then
            if [ "$SYNC_DISTANCE" -lt 32 ]; then
                log_info "  Finalizing sync, almost complete..."
                log_info "  Slots behind: ${SYNC_DISTANCE}"
            else
                HEAD_EPOCH=$((HEAD_SLOT / 32))
                TARGET_SLOT=$((HEAD_SLOT + SYNC_DISTANCE))
                TARGET_EPOCH=$((TARGET_SLOT / 32))

                SYNC_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($HEAD_SLOT / $TARGET_SLOT) * 100}")
                log_info "  Sync progress: ${SYNC_PERCENT}%"
                log_info "  Current slot: ${HEAD_SLOT} (epoch ${HEAD_EPOCH})"
                log_info "  Target slot: ${TARGET_SLOT} (epoch ${TARGET_EPOCH})"
                log_info "  Slots behind: ${SYNC_DISTANCE}"
            fi
        fi

        CONSENSUS_SYNC_LOG=$(ansible validator -i inventory/hosts.yml -m shell -a "journalctl -u consensus --since '10 minutes ago' --no-pager | grep ' sync=\"\' | tail -1" 2>/dev/null || echo "")
        CONSENSUS_SYNC_DETAIL=$(echo "$CONSENSUS_SYNC_LOG" | sed -n 's/.* sync=\"\([^"]\+\\\)\".*/\1/p')

        if [ -n "$CONSENSUS_SYNC_DETAIL" ]; then
            SYNC_REMAINING=$(echo "$CONSENSUS_SYNC_DETAIL" | awk '{print $1}')
            SYNC_PERCENT_DETAIL=$(echo "$CONSENSUS_SYNC_DETAIL" | sed 's/.*(\([^)]*\)).*/\1/' || echo "n/a")
            SYNC_SPEED=$(echo "$CONSENSUS_SYNC_DETAIL" | awk '{print $2}')

            if [ -n "$SYNC_REMAINING" ]; then
                log_info "  Nimbus log estimate: ${SYNC_REMAINING} remaining (~${SYNC_PERCENT_DETAIL:-n/a}) at ${SYNC_SPEED:-n/a}"
            fi
        fi
    fi
fi

CONSENSUS_PEERS=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s http://127.0.0.1:5052/eth/v1/node/peer_count" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="connected"){print $(i+2)}}}' || echo "0")

if [ "$CONSENSUS_PEERS" != "0" ] && [ "$CONSENSUS_PEERS" != "" ]; then
    log_success "Connected to ${CONSENSUS_PEERS} consensus peers"
else
    log_warning "No consensus peers connected"
    OVERALL_HEALTH=1
fi

echo ""

if [ "$VALIDATOR_RUNNING" = true ]; then
    print_header "━━━ Validator Status ━━━"

    VALIDATOR_KEYS=$(ssh ${REMOTE_HOST} "sudo find /run/validator-keys -name 'keystore-*.json' -exec basename {} .json \; 2>/dev/null | sed 's/^keystore-//'" 2>/dev/null || echo "")

    if [ -z "$VALIDATOR_KEYS" ]; then
        echo ""
        log_warning "No validator keys found"
        log_info "  Import validator keys to begin validation"
        log_info "  Command: task validator:deploy:keys"
    else
        KEY_COUNT=$(echo "$VALIDATOR_KEYS" | wc -l)
        log_success "Found ${KEY_COUNT} validator key(s)"
        echo ""

        if [ "$CONSENSUS_SYNC" = "false" ] && [ -n "$CURRENT_SLOT" ]; then
            VALIDATOR_NUM=1
            while IFS= read -r KEYSTORE_ID; do
                if [ -z "$KEYSTORE_ID" ]; then
                    continue
                fi

                # Extract public key from keystore file
                VALIDATOR_PUBKEY_RAW=$(ssh ${REMOTE_HOST} "sudo jq -r '.pubkey' /run/validator-keys/keystore-${KEYSTORE_ID}.json 2>/dev/null" 2>/dev/null || echo "")
                VALIDATOR_PUBKEY=$(ensure_hex_key "$VALIDATOR_PUBKEY_RAW")

                if [ -z "$VALIDATOR_PUBKEY" ]; then
                    log_warning "Validator ${VALIDATOR_NUM}: Could not read pubkey from keystore-${KEYSTORE_ID}.json"
                    VALIDATOR_NUM=$((VALIDATOR_NUM + 1))
                    continue
                fi

                TRUNCATED_KEY=$(truncate_pubkey "$VALIDATOR_PUBKEY")
                VALIDATOR_STATUS_RESPONSE=$(ansible validator -i inventory/hosts.yml -m shell -a "curl -s http://127.0.0.1:5052/eth/v1/beacon/states/head/validators/${VALIDATOR_PUBKEY}" 2>/dev/null || echo "")

                if [ -z "$VALIDATOR_STATUS_RESPONSE" ] || echo "$VALIDATOR_STATUS_RESPONSE" | grep -q "error\|NOT_FOUND"; then
                    log_warning "Validator ${VALIDATOR_NUM}: ${TRUNCATED_KEY}"
                    log_info "  Status: Not yet deposited or not found on chain"
                    log_info "  Action: Ensure deposit was made and confirmed"
                else
                    VALIDATOR_INDEX=$(echo "$VALIDATOR_STATUS_RESPONSE" | sed -n 's/.*"index":"\([^"]\+\).*/\1/p')
                    VALIDATOR_STATUS=$(echo "$VALIDATOR_STATUS_RESPONSE" | sed -n 's/.*"status":"\([^"]\+\).*/\1/p')
                    VALIDATOR_BALANCE=$(echo "$VALIDATOR_STATUS_RESPONSE" | sed -n 's/.*"balance":"\([^"]\+\).*/\1/p')
                    EFFECTIVE_BALANCE=$(echo "$VALIDATOR_STATUS_RESPONSE" | sed -n 's/.*"effective_balance":"\([^"]\+\).*/\1/p')

                    # Convert balance from Gwei to ETH (divide by 1000000000)
                    if [ -n "$VALIDATOR_BALANCE" ]; then
                        BALANCE_ETH=$(awk "BEGIN {printf \"%.4f\", $VALIDATOR_BALANCE / 1000000000}")
                    else
                        BALANCE_ETH="0"
                    fi

                    # Determine status emoji and message
                    case "$VALIDATOR_STATUS" in
                        "active_ongoing")
                            STATUS_EMOJI="✅"
                            STATUS_MSG="ACTIVE and attesting"
                            ;;
                        "active_exiting")
                            STATUS_EMOJI="⚠️"
                            STATUS_MSG="EXITING"
                            ;;
                        "pending_initialized"|"pending_queued")
                            STATUS_EMOJI="⏳"
                            STATUS_MSG="PENDING activation"
                            ;;
                        "exited_unslashed")
                            STATUS_EMOJI="💤"
                            STATUS_MSG="EXITED (clean)"
                            ;;
                        "exited_slashed")
                            STATUS_EMOJI="❌"
                            STATUS_MSG="SLASHED"
                            ;;
                        *)
                            STATUS_EMOJI="❓"
                            STATUS_MSG="$VALIDATOR_STATUS"
                            ;;
                    esac

                    echo "${STATUS_EMOJI} Validator ${VALIDATOR_NUM}: ${TRUNCATED_KEY}"
                    log_info "  Index: ${VALIDATOR_INDEX}"
                    log_info "  Status: ${STATUS_MSG}"
                    log_info "  Balance: ${BALANCE_ETH} ETH"

                    if [ "$VALIDATOR_STATUS" = "active_ongoing" ]; then
                        log_success "${VALIDATOR_NUM} Validator \"${VALIDATOR_PUBKEY}\" is active and attesting on slot ${CURRENT_SLOT}"

                        CURRENT_EPOCH_LOCAL=$((CURRENT_SLOT / 32))
                        NEXT_ATTESTATION_EPOCH=$((CURRENT_EPOCH_LOCAL + 1))
                        NEXT_ATTESTATION_SLOT=$((NEXT_ATTESTATION_EPOCH * 32))

                        log_info "  Next attestation expected at slot ${NEXT_ATTESTATION_SLOT} (epoch ${NEXT_ATTESTATION_EPOCH})"
                    fi

                    echo ""
                fi

                VALIDATOR_NUM=$((VALIDATOR_NUM + 1))
            done <<< "$VALIDATOR_KEYS"
        else
            log_warning "Chain is still syncing"
            log_info "  Validator status will be available once chain is synced"

            # Get latest "Slot start" from any relevant unit (compact one-liner to avoid quoting pitfalls)
            SLOT_LINE=$(ssh "${REMOTE_HOST}" 'sudo journalctl -n 200 --no-pager -q -u validator -u nimbus_validator_client -u consensus -u nimbus_beacon_node | grep -F "Slot start" | tail -1' 2>/dev/null || true)

            SLOT_FROM_LOG=""
            EPOCH_FROM_LOG=""

            if [ -n "$SLOT_LINE" ]; then
              SLOT_FROM_LOG=$(printf '%s' "$SLOT_LINE" | sed -E 's/.*slot=([0-9]+).*/\1/')
              EPOCH_FROM_LOG=$(printf '%s' "$SLOT_LINE" | sed -E 's/.*epoch=([0-9]+).*/\1/')
            fi

            # Fallbacks: HEAD_SLOT/HEAD_EPOCH from consensus API (computed earlier)
            if [ -z "$SLOT_FROM_LOG" ] && [ -n "${HEAD_SLOT:-}" ]; then
              SLOT_FROM_LOG="$HEAD_SLOT"
            fi
            # ensure HEAD_EPOCH exists if we have HEAD_SLOT
            if [ -z "${HEAD_EPOCH:-}" ] && [ -n "${HEAD_SLOT:-}" ]; then
              HEAD_EPOCH=$((HEAD_SLOT / 32))
            fi
            if [ -z "$EPOCH_FROM_LOG" ] && [ -n "${HEAD_EPOCH:-}" ]; then
              EPOCH_FROM_LOG="$HEAD_EPOCH"
            elif [ -z "$EPOCH_FROM_LOG" ] && [ -n "$SLOT_FROM_LOG" ]; then
              EPOCH_FROM_LOG=$((SLOT_FROM_LOG / 32))
            fi

            # Print when available
            [ -n "$SLOT_FROM_LOG" ]  && log_info "  Current slot: ${SLOT_FROM_LOG}"
            [ -n "$EPOCH_FROM_LOG" ] && log_info "  Current epoch: ${EPOCH_FROM_LOG}"

            # List validator keys (use process substitution instead of here-string to avoid parse edge-cases)
            VALIDATOR_NUM=1
            while IFS= read -r KEYSTORE_ID; do
              [ -z "$KEYSTORE_ID" ] && continue

              VALIDATOR_PUBKEY_RAW=$(ssh "${REMOTE_HOST}" "sudo jq -r '.pubkey' /run/validator-keys/keystore-${KEYSTORE_ID}.json 2>/dev/null" 2>/dev/null || echo "")

              if [ -z "$VALIDATOR_PUBKEY_RAW" ]; then
                TRUNCATED_KEY="keystore-${KEYSTORE_ID}"
              else
                VALIDATOR_PUBKEY=$(ensure_hex_key "$VALIDATOR_PUBKEY_RAW")
                TRUNCATED_KEY=$(truncate_pubkey "$VALIDATOR_PUBKEY")
                [ -z "$TRUNCATED_KEY" ] && TRUNCATED_KEY="keystore-${KEYSTORE_ID}"
              fi

              log_info "  Validator ${VALIDATOR_NUM}: ${TRUNCATED_KEY}"
              VALIDATOR_NUM=$((VALIDATOR_NUM + 1))
            done < <(printf '%s\n' "$VALIDATOR_KEYS")
        fi
    fi
fi

print_header "━━━ Resource Usage ━━━"
echo ""

# Get disk usage with more detail
DISK_INFO=$(ansible validator -i inventory/hosts.yml -m shell -a "df -h /validator | tail -n1" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")
if [ -n "$DISK_INFO" ]; then
    DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
    DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}')
    log_info "Disk usage: ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT})"
else
    log_info "Disk usage: N/A"
fi

# Get memory usage
MEM_INFO=$(ansible validator -i inventory/hosts.yml -m shell -a "free -h | grep Mem" 2>/dev/null | grep -v "CHANGED\|rc=0\|>>" || echo "")
if [ -n "$MEM_INFO" ]; then
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    log_info "Memory usage: ${MEM_USED}/${MEM_TOTAL}"
else
    log_info "Memory usage: N/A"
fi

echo ""

print_header "━━━ Health Summary ━━━"
echo ""

case $OVERALL_HEALTH in
    0)
        log_success "Status: ${GREEN}${BOLD}HEALTHY${NC}"
        echo ""
        echo "  ✅ All systems operational and fully synced"
        echo "  ✅ Execution client synced to latest block"
        echo "  ✅ Consensus client synced to latest slot"
        if [ "$VALIDATOR_RUNNING" = true ]; then
            echo "  ✅ Validator client running and ready"
        fi
        echo ""
        log_info "Your validator is ready to perform duties!"
        EXIT_CODE=0
        ;;
    1)
        log_warning "Status: ${YELLOW}${BOLD}SYNCING${NC}"
        echo ""
        echo "  ⏳ Clients are syncing to network"
        echo "  ℹ️  This is normal for new deployments"
        echo ""
        log_info "Estimated sync time:"
        log_info "  • Execution client: 2-4 hours (depending on network)"
        log_info "  • Consensus client: 15-30 minutes (with checkpoint sync)"
        log_info "Re-run this check periodically to monitor progress."
        EXIT_CODE=0
        ;;
    2)
        log_error "Status: ${RED}${BOLD}UNHEALTHY${NC}"
        echo ""
        echo "  ❌ One or more critical services are down"
        echo "  ⚠️  Validator cannot attest in this state"
        echo ""
        log_error "Action required: Check service logs for errors"
        EXIT_CODE=1
        ;;
esac

exit $EXIT_CODE
