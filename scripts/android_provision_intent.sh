#!/usr/bin/env bash
# ==============================================================================
# Android eUICC Intent Dispatcher
# Dispatches Android eSIM activation intent and launches Google Fi app
# Device Hardware: 359470646111783 / 359470646111791 (EID: 89033023427100000000009924552528)
# ==============================================================================
set -euo pipefail

CARDDATA="LPA%3A1%24t-mobile.esim.prod%24TMOBILE_5G_UL_PLUS_846759%249021"
PROV_URL="https://esimsetup.android.com/esim_qrcode_provisioning?carddata=${CARDDATA}"

echo "[*] Dispatching Android eUICC Provisioning URL intent..."
if command -v am >/dev/null 2>&1; then
    # Direct eUICC intent
    am start -a android.intent.action.VIEW -d "${PROV_URL}" || true
    
    # Launch Google Fi cellular manager
    am start -n com.google.android.apps.fi/.ui.MainActivity || true
    
    # Open Android eUICC Settings
    am start -a android.settings.EUICC_SETTINGS || true
    
    echo "[✔] Intents dispatched to Android Activity Manager."
else
    echo "[i] 'am' tool not available in this environment. Open this URL on Android device:"
    echo "${PROV_URL}"
fi
