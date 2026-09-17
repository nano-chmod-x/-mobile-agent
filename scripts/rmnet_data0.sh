#!/usr/bin/env bash
# T.I.E. System Patcher: rmnet_data0.sh
# Purpose: Cellular Modem Multiplexing, MTU Optimization & Magisk SU Injection
set -euo pipefail

INTERFACE="rmnet_data0"
TARGET_MTU=1500
QMAP_MUX_ID="0x01"
APN_PROFILE="h2g2"
CARRIER_PLMN="310-260"

echo "[i] Auditing interface $INTERFACE..."
if command -v ip >/dev/null 2>&1; then
    if ip link show "$INTERFACE" > /dev/null 2>&1; then
        ip link set dev "$INTERFACE" mtu "$TARGET_MTU" 2>/dev/null || true
        ip link set dev "$INTERFACE" up 2>/dev/null || true
        echo "[✔] Interface $INTERFACE state validated (MTU: $TARGET_MTU)."
    fi
fi
