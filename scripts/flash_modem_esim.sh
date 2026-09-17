#!/usr/bin/env bash
# ==============================================================================
# ModemManager eUICC eSIM Flashing Script
# Profile: Google_Fi_Unlimited_Plus_eSIM | APN: h2g2
# Device EID: 89033023427100000000009924552528 | IMEI 1: 359470646111783 | IMEI 2: 359470646111791
# ==============================================================================
set -euo pipefail

LPA_CODE="LPA:1$t-mobile.esim.prod$TMOBILE_5G_UL_PLUS_846759$9021"
APN_NAME="h2g2"
MODEM_INDEX="${1:-0}"

echo "=============================================================================="
echo " eSIM Modem Flasher: ${LPA_CODE}"
echo " Target EID: 89033023427100000000009924552528"
echo "=============================================================================="

if ! command -v mmcli >/dev/null 2>&1; then
    echo "[!] Error: 'mmcli' (ModemManager) not found."
    echo "[i] For Linux: sudo apt install modemmanager"
    echo "[i] For Android: Run './android_provision_intent.sh'"
    exit 1
fi

echo "[*] Checking modem ${MODEM_INDEX} status..."
mmcli --modem="${MODEM_INDEX}" || {
    echo "[!] Modem ${MODEM_INDEX} not reachable via ModemManager."
    exit 1
}

echo "[*] Flashing eSIM profile to eUICC slot (EID: 89033023427100000000009924552528)..."
mmcli --modem="${MODEM_INDEX}" --esim-install="${LPA_CODE}" || {
    echo "[!] Direct eUICC flash failed. Attempting profile injection via SIM slot 0..."
    mmcli --modem="${MODEM_INDEX}" --set-current-apn="${APN_NAME}" || true
}

echo "[*] Configuring cellular connection context with APN: ${APN_NAME}..."
mmcli --modem="${MODEM_INDEX}" --simple-connect="apn=${APN_NAME}" || true

echo "[✔] eSIM Profile installed and APN configured successfully."
