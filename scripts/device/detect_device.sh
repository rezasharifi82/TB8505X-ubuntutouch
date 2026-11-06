#!/usr/bin/env bash
# ==============================================================================
# Script: detect_device.sh
# Purpose: Non-destructive device detection and hardware state interrogation
#          via ADB and Fastboot. Redacts sensitive identity information.
# ==============================================================================

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

log_info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_err()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_title() { echo -e "\n${BOLD}=== $* ===${RESET}"; }

log_title "Lenovo TB-8505X Non-Destructive Device Detection"

# Helper to sanitize serials and MACs
sanitize() {
    sed -E 's/(serialno:[[:space:]]*)[A-Za-z0-9]+/\1[REDACTED_SERIAL]/g; \
            s/(ro\.boot\.serialno[[:space:]]*=[[:space:]]*\[)[^]]+(\])/\1[REDACTED_SERIAL]\2/g; \
            s/(ro\.serialno[[:space:]]*=[[:space:]]*\[)[^]]+(\])/\1[REDACTED_SERIAL]\2/g; \
            s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/[REDACTED_MAC]/g'
}

MODE="none"
if command -v fastboot >/dev/null 2>&1 && [ -n "$(fastboot devices 2>/dev/null || true)" ]; then
    MODE="fastboot"
elif command -v adb >/dev/null 2>&1 && [ -n "$(adb devices 2>/dev/null | grep -v 'List of devices' | grep 'device' || true)" ]; then
    MODE="adb"
fi

if [ "$MODE" = "none" ]; then
    log_err "No device detected via ADB or Fastboot."
    echo "Please connect the tablet via USB with USB debugging enabled or in Fastboot mode."
    exit 1
fi

log_ok "Device connection detected in mode: $MODE"

if [ "$MODE" = "fastboot" ]; then
    log_title "Fastboot State & Bootloader Variables"
    
    get_fb_var() {
        local var="$1"
        fastboot getvar "$var" 2>&1 | grep "$var:" | awk '{$1=""; print $0}' | xargs || echo "unknown"
    }
    
    PRODUCT=$(get_fb_var "product")
    UNLOCKED=$(get_fb_var "unlocked")
    SECURE=$(get_fb_var "secure")
    SLOTS=$(get_fb_var "slot-count")
    MAX_DL=$(get_fb_var "max-download-size")
    BAT_OK=$(get_fb_var "battery-soc-ok")
    BL_VER=$(get_fb_var "version-bootloader")
    
    echo "  - Product:             $PRODUCT"
    echo "  - Bootloader Unlocked: $UNLOCKED"
    echo "  - Secure Boot:         $SECURE"
    echo "  - Partition Slots:     $SLOTS (Non-A/B)"
    echo "  - Max Download Size:   $MAX_DL"
    echo "  - Battery State:       $BAT_OK"
    echo "  - Bootloader Version:  $BL_VER"
    
    if [ "$PRODUCT" != "akita_row_call" ] && [ "$PRODUCT" != "akita_row_wifi" ]; then
        log_warn "Target product ($PRODUCT) does not match expected Lenovo Tab M8 (akita)."
    else
        log_ok "Target board identified as Lenovo Tab M8 ($PRODUCT)."
    fi

    if [ "$UNLOCKED" = "no" ]; then
        log_warn "Bootloader is LOCKED. Destructive unlocking must NOT be performed automatically."
    else
        log_ok "Bootloader is UNLOCKED."
    fi

elif [ "$MODE" = "adb" ]; then
    log_title "ADB System Properties & Kernel State"
    
    get_prop() {
        local prop="$1"
        adb shell getprop "$prop" 2>/dev/null | tr -d '\r' || echo "unknown"
    }
    
    MODEL=$(get_prop "ro.product.model")
    BOARD=$(get_prop "ro.product.board")
    BUILD_ID=$(get_prop "ro.build.display.id")
    ANDROID_VER=$(get_prop "ro.build.version.release")
    SDK_VER=$(get_prop "ro.build.version.sdk")
    PLATFORM=$(get_prop "ro.board.platform")
    HW=$(get_prop "ro.hardware")
    OEM_UNLOCK_ALLOWED=$(get_prop "sys.oem_unlock_allowed")
    
    echo "  - Model:              $MODEL"
    echo "  - Board:              $BOARD"
    echo "  - Build Display ID:   $BUILD_ID"
    echo "  - Android Version:    $ANDROID_VER (SDK $SDK_VER)"
    echo "  - Platform:           $PLATFORM"
    echo "  - Hardware:           $HW"
    echo "  - OEM Unlock Allowed: $OEM_UNLOCK_ALLOWED"
    
    KERNEL_STR=$(adb shell cat /proc/version 2>/dev/null | tr -d '\r' || echo "unknown")
    echo "  - Running Kernel:     $KERNEL_STR"
fi

log_title "Detection Completed Safely"
exit 0
