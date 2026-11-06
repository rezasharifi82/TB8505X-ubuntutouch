#!/usr/bin/env bash
# ==============================================================================
# Script: validate_kernel.sh
# Purpose: Comprehensive host-side validation of compiled kernel and .config
# Target: MediaTek MT6761 / MT8766B (akita_row_call)
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$HERE/workdir/downloads/KERNEL_OBJ/.config"
IMAGE_FILE="$HERE/workdir/downloads/KERNEL_OBJ/arch/arm64/boot/Image"
IMAGE_GZ="$HERE/workdir/downloads/KERNEL_OBJ/arch/arm64/boot/Image.gz"
DTB_FILE="$HERE/workdir/downloads/akita_row_call.dtb"

BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

log_info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_err()  { echo -e "${RED}[ERROR]${RESET} $*"; }

echo -e "\n${BOLD}=== Kernel Validation for Lenovo TB-8505X ===${RESET}\n"

ERRORS=0

# 1. Binary existence
log_info "1. Checking kernel binary artifacts..."
if [ -f "$IMAGE_FILE" ] && [ -f "$IMAGE_GZ" ]; then
    log_ok "Kernel Image exists ($(stat -c %s "$IMAGE_FILE") bytes uncompressed, $(stat -c %s "$IMAGE_GZ") bytes gzip)"
else
    log_err "Kernel image binaries missing!"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$DTB_FILE" ]; then
    log_ok "Merged DTB exists ($(stat -c %s "$DTB_FILE") bytes)"
else
    log_err "DTB file missing!"
    ERRORS=$((ERRORS + 1))
fi

# 2. Monolithic verification
log_info "2. Checking module configuration..."
if [ -f "$CONFIG_FILE" ]; then
    MODULES_COUNT=$(grep "=m" "$CONFIG_FILE" 2>/dev/null | wc -l || true)
    if [ "$MODULES_COUNT" -eq 0 ]; then
        log_ok "Kernel is strictly monolithic (0 loadable modules configured)"
    else
        log_err "Found $MODULES_COUNT loadable modules! Kernel must be monolithic."
        ERRORS=$((ERRORS + 1))
    fi
else
    log_err "Kernel .config missing!"
    ERRORS=$((ERRORS + 1))
fi

# 3. Security & AppArmor Subsystem
log_info "3. Validating Ubuntu Touch AppArmor LSM configuration..."
check_kconfig() {
    local sym="$1"
    local expected="$2"
    local val
    val=$(grep "^${sym}=" "$CONFIG_FILE" || echo "${sym}=NOT_SET")
    if [ "$val" = "${sym}=${expected}" ]; then
        log_ok "$sym=$expected"
    else
        log_err "Mismatch: expected ${sym}=${expected}, got $val"
        ERRORS=$((ERRORS + 1))
    fi
}

check_kconfig "CONFIG_SECURITY_APPARMOR" "y"
check_kconfig "CONFIG_DEFAULT_SECURITY_APPARMOR" "y"

# 4. Container & LXC isolation
log_info "4. Validating Container Namespaces & Cgroups..."
check_kconfig "CONFIG_NAMESPACES" "y"
check_kconfig "CONFIG_USER_NS" "y"
check_kconfig "CONFIG_PID_NS" "y"
check_kconfig "CONFIG_NET_NS" "y"
check_kconfig "CONFIG_CGROUPS" "y"
check_kconfig "CONFIG_DEVTMPFS" "y"
check_kconfig "CONFIG_DEVTMPFS_MOUNT" "y"

# 5. IPC & Binder (Linux 4.9 Static Device Nodes)
log_info "5. Validating Android Binder IPC interfaces..."
check_kconfig "CONFIG_ANDROID_BINDER_IPC" "y"
BINDER_DEVICES=$(grep "^CONFIG_ANDROID_BINDER_DEVICES=" "$CONFIG_FILE" || true)
if [[ "$BINDER_DEVICES" == *"binder"* ]] && [[ "$BINDER_DEVICES" == *"hwbinder"* ]] && [[ "$BINDER_DEVICES" == *"vndbinder"* ]]; then
    log_ok "$BINDER_DEVICES"
else
    log_err "Missing standard binder devices in $BINDER_DEVICES"
    ERRORS=$((ERRORS + 1))
fi

# 6. Hardware Drivers
log_info "6. Validating Built-in Hardware Drivers..."
check_kconfig "CONFIG_MTK_GPU_SUPPORT" "y"
check_kconfig "CONFIG_TOUCHSCREEN_MTK_FOCALTECH_TS" "y"
check_kconfig "CONFIG_MTK_PMIC_CHIP_MT6357" "y"

# 7. Compiler banner inspection
log_info "7. Inspecting kernel compiler string..."
BANNER=$(strings "$IMAGE_FILE" | grep "Linux version 4.9.190+" | head -n 1 || true)
if [ -n "$BANNER" ]; then
    log_ok "Banner verified: $BANNER"
else
    log_err "Could not find expected Linux version banner in decompressed Image!"
    ERRORS=$((ERRORS + 1))
fi

echo -e "\n${BOLD}=== Validation Summary ===${RESET}"
if [ "$ERRORS" -eq 0 ]; then
    log_ok "All kernel validation tests PASSED!"
    exit 0
else
    log_err "$ERRORS validation checks failed!"
    exit 1
fi
