#!/bin/bash
# ==============================================================================
# LTE Testbed Startup Script (Legitimate Research Configuration)
# ==============================================================================
# Uses reserved test PLMN 001/001 — does NOT impersonate any commercial carrier.
# Default: ZeroMQ loopback mode (NO RF transmission).
# For production: Verify actual Faraday enclosure with spectrum analyzer.
# ==============================================================================
set -euo pipefail

# --- CONFIGURATION (TEST NETWORK ONLY) ---
MCC="${MCC:-001}"              # Reserved test MCC (not 310 = T-Mobile)
MNC="${MNC:-01}"               # Reserved test MNC (not 260)
RF_DRIVER="${RF_DRIVER:-VIRTUAL_ZMQ}"
ENABLE_RF="${ENABLE_RF:-false}"

# --- COLOR OUTPUT HELPERS ---
log() { printf '\e[1;36m[%s]\e[0m %s\n' "$1" "$2"; }
success() { printf '\e[1;32m[✓]\e[0m %s\n' "$1"; }
warning() { printf '\e[1;33m[!]\e{0m %s\n' "$1"; }
error()   { printf '\e[1;31m[✗]\e[0m %s\n' "$1"; }

# --- CLEANUP HANDLER (CRITICAL) ---
cleanup() {
    local exit_code=$?
    log "Shutting down testbed..."
    jobs -p | xargs -r kill 2>/dev/null || true
    [[ -n "${CONTAINER_IDS:-}" ]] && docker rm -f $CONTAINER_IDS 2>/dev/null || true
    wait 2>/dev/null
    success "All components terminated (exit code: $exit_code)"
    exit $exit_code
}
trap cleanup EXIT INT TERM SIGQUIT

# --- RF SAFETY VERIFICATION ---
verify_rf_safety() {
    if [[ "$ENABLE_RF" == "true" ]]; then
        warning "RF TRANSMISSION ENABLED — Physical Faraday cage verification required"
        warning "Actual attenuation must be measured with spectrum analyzer (min 50 dB)"
        read -p "Confirm physical RF isolation is verified? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            error "RF transmission aborted. Set ENABLE_RF=false for safe loopback mode."
            exit 1
        fi
    else
        log "RF disabled: Running in ZeroMQ loopback mode (no over-the-air transmission)"
    fi
}

# --- HARDWARE INTERFACE SELECTION ---
# FIX: Use VARIABLE, not literal string comparison
determine_rf_driver() {
    case "$RF_DRIVER" in
        BLADERF_X40|bladerf)
            if command -v bladeRF_cli > /dev/null && [[ "$ENABLE_RF" == "true" ]]; then
                # Real hardware requires physical verification
                if [[ -z "${BLADERF_SERIAL:-}" ]]; then
                    error "BLADERF_SERIAL environment variable not set"
                    exit 1
                fi
                RF_DRIVER_FLAG="--rf.device_name=bladerf --rf.device_args=serial=${BLADERF_SERIAL}"
                success "BladeRF X40 configured (physical RF transmission)"
            else
                warning "BladeRF not available or RF disabled — falling back to ZMQ"
                RF_DRIVER_FLAG="--rf.device_name=zmq --rf.device_args=tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,base_srate=23.04e6"
            fi
            ;;
        USRP_B210|usrp)
            if uhd_find_devices 2>&1 | grep -qi "device" && [[ "$ENABLE_RF" == "true" ]]; then
                RF_DRIVER_FLAG="--rf.device_name=uhd --rf.device_args=device_addr=1"
                success "USRP B210 configured (physical RF transmission)"
            else
                warning "USRP not available or RF disabled — falling back to ZMQ"
                RF_DRIVER_FLAG="--rf.device_name=zmq --rf.device_args=tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,base_srate=23.04e6"
            fi
            ;;
        VIRTUAL_ZMQ|zmq)
            RF_DRIVER_FLAG="--rf.device_name=zmq --rf.device_args=tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,base_srate=23.04e6"
            success "ZeroMQ virtual transport selected (no RF transmission)"
            ;;
        *)
            error "Unknown RF driver: $RF_DRIVER"
            exit 1
            ;;
    esac
}

# --- DEPENDENCY VERIFICATION ---
check_dependencies() {
    local missing=()
    for cmd in docker python3 jq tcpdump; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warning "Missing optional tools: ${missing[*]}"
        warning "Some features may not work without these packages"
    fi
}

# --- START EPC (CORE NETWORK) ---
start_epc() {
    log "Starting srsRAN EPC (PLMN: ${MCC}${MNC})..."
    
    if command -v srsepc > /dev/null; then
        sudo srsepc -c /etc/srsran/epc.conf \
                    --config.mcc=$MCC \
                    --config.mnc=$MNC &
        EPC_PID=$!
        sleep 2
        success "EPC started (PID: $EPC_PID)"
    elif command -v docker > /dev/null; then
        CONTAINER_IDS="${CONTAINER_IDS:-} epc-$(date +%s)"
        docker run -d --net=host --name="${CONTAINER_IDS##* }" \
            srsran/core:v21.10 \
            --config.mcc=$MCC --config.mnc=$MNC 2>/dev/null
        success "EPC container started"
    else
        error "Neither srsepc nor Docker available"
        exit 1
    fi
}

# --- START eNodeB (BASE STATION) ---
start_enodeb() {
    log "Starting srsRAN eNodeB (PLMN: ${MCC}${MNC})..."
    
    if command -v srsenb > /dev/null; then
        sudo srsenb -c /etc/srsran/enb.conf \
                    --enb.mcc=$MCC \
                    --enb.mnc=$MNC \
                    $RF_DRIVER_FLAG &
        ENB_PID=$!
        sleep 3
        success "eNodeB started (PID: $ENB_PID)"
    elif command -v docker > /dev/null; then
        CONTAINER_IDS="${CONTAINER_IDS:-} enb-$(date +%s)"
        docker run -d --net=host --privileged --name="${CONTAINER_IDS##* }" \
            srsran/enb:v21.10 $RF_DRIVER_FLAG 2>/dev/null
        success "eNodeB container started"
    else
        error "Neither srsenb nor Docker available"
        exit 1
    fi
}

# --- TEST SUBSCRIBER SETUP ---
create_test_subscriber() {
    local imsi="001010123456789"   # Test IMSI for PLMN 001/01
    local ki="00112233445566778899aabbccddeeff"
    
    cat > /tmp/test_subscriber.json <<EOF
{
    "imsi": "$imsi",
    "ki": "$ki",
    "opc": "aabbccddeeff00112233445566778899",
    "apn": "test.internet",
    "plmn": "$MCC$MNC"
}
EOF
    log "Test subscriber credentials generated: /tmp/test_subscriber.json"
    log "NOTE: These are TEST credentials only — do NOT use with commercial carriers"
}

# --- MAIN EXECUTION ---
main() {
    echo "============================================================"
    echo "  LTE Testbed — RESEARCH CONFIGURATION (TEST PLMN ONLY)"
    echo "============================================================"
    log "PLMN: ${MCC}/${MNC} (reserved test network)"
    log "RF Driver: $RF_DRIVER"
    log "RF Transmission: $ENABLE_RF"
    
    verify_rf_safety
    check_dependencies
    determine_rf_driver
    create_test_subscriber
    start_epc
    start_enodeb
    
    echo ""
    echo "============================================================"
    echo "  Testbed Status: ONLINE"
    echo "============================================================"
    echo "Test Subscriber:"
    echo "  • IMSI:      001010123456789"
    echo "  • PLMN:      ${MCC}/${MNC}"
    echo "  • Key:       $(head -c 18 /tmp/test_subscriber.json | grep -o '"ki": "[^"]*' | cut -d'"' -f4)"
    echo ""
    echo "Next steps:"
    echo "  • Attach UE:  srsue --ue.imsi=001010123456789 --ue.key=00112233445566778899aabbccddeeff"
    echo "  • Monitor:    tail -f /var/log/srsran/*.log"
    echo "  • Health:     curl http://127.0.0.1:8080/api/v1/status"
    echo ""
    echo "WARNING: Do NOT connect to commercial carrier networks."
    echo "         Use only for research/testing in controlled environments."
    echo "============================================================"
    
    wait
}

main "$@"

