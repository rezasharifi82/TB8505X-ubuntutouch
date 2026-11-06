#!/usr/bin/env bash
# ==============================================================================
# Script: validate_installation_package.sh
# Purpose: Comprehensive automated validation of the Ubuntu Touch installation package
# Target: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$HERE/out"
UNPACK_BOOT="$HERE/workdir/downloads/android_system_tools_mkbootimg/unpack_bootimg.py"

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

echo -e "\n${BOLD}=== Automated Validation of Ubuntu Touch Installation Package ===${RESET}\n"

ERRORS=0

# 1. Artifact existence
log_info "1. Checking release artifacts in out/..."
for artifact in boot.img recovery.img device_akita_row_call.tar.xz SHA256SUMS.txt; do
    if [ -f "$OUT_DIR/$artifact" ]; then
        log_ok "$artifact exists ($(stat -c %s "$OUT_DIR/$artifact") bytes)"
    else
        log_err "Missing artifact: $artifact"
        ERRORS=$((ERRORS + 1))
    fi
done

# 2. Checksum validation
log_info "2. Verifying SHA-256 checksum manifest..."
if [ -f "$OUT_DIR/SHA256SUMS.txt" ]; then
    (cd "$OUT_DIR" && sha256sum -c SHA256SUMS.txt) || {
        log_err "Checksum verification failed!"
        ERRORS=$((ERRORS + 1))
    }
fi

# 3. Boot & Recovery Partition Size Constraints
log_info "3. Verifying image sizes against physical GPT limits..."
MAX_BOOT_SIZE=33554432 # 32 MiB

BOOT_SIZE=$(stat -c %s "$OUT_DIR/boot.img")
if [ "$BOOT_SIZE" -eq "$MAX_BOOT_SIZE" ]; then
    log_ok "boot.img size is exactly 33,554,432 bytes (matches physical boot mmcblk0p28)"
elif [ "$BOOT_SIZE" -lt "$MAX_BOOT_SIZE" ]; then
    log_warn "boot.img size is $BOOT_SIZE bytes (< $MAX_BOOT_SIZE). AVB footer might not pad to full partition."
else
    log_err "boot.img exceeds partition size! ($BOOT_SIZE > $MAX_BOOT_SIZE)"
    ERRORS=$((ERRORS + 1))
fi

REC_SIZE=$(stat -c %s "$OUT_DIR/recovery.img")
if [ "$REC_SIZE" -eq "$MAX_BOOT_SIZE" ]; then
    log_ok "recovery.img size is exactly 33,554,432 bytes (matches physical recovery mmcblk0p2)"
elif [ "$REC_SIZE" -lt "$MAX_BOOT_SIZE" ]; then
    log_warn "recovery.img size is $REC_SIZE bytes (< $MAX_BOOT_SIZE)."
else
    log_err "recovery.img exceeds partition size! ($REC_SIZE > $MAX_BOOT_SIZE)"
    ERRORS=$((ERRORS + 1))
fi

# 4. Header & Ramdisk Inspection of boot.img
log_info "4. Inspecting boot.img structure via unpack_bootimg..."
TEMP_UNPACK_BOOT=$(mktemp -d)
python3 "$UNPACK_BOOT" --boot_img "$OUT_DIR/boot.img" --out "$TEMP_UNPACK_BOOT" >/dev/null

RAMDISK_SIZE=$(stat -c %s "$TEMP_UNPACK_BOOT/ramdisk" 2>/dev/null || echo 0)
if [ "$RAMDISK_SIZE" -gt 0 ]; then
    log_ok "boot.img ramdisk present ($RAMDISK_SIZE bytes)"
    if (zcat "$TEMP_UNPACK_BOOT/ramdisk" | cpio -t | grep "scripts/halium" >/dev/null 2>&1); then
        log_ok "boot.img contains verified initramfs-tools-halium boot scripts"
    else
        log_err "boot.img ramdisk missing scripts/halium!"
        ERRORS=$((ERRORS + 1))
    fi
else
    log_err "boot.img ramdisk is 0 bytes! Must contain Halium initramfs."
    ERRORS=$((ERRORS + 1))
fi
rm -rf "$TEMP_UNPACK_BOOT"

# 5. Recovery Ramdisk Inspection
log_info "5. Inspecting recovery.img ramdisk for device recovery.fstab..."
TEMP_UNPACK_REC=$(mktemp -d)
python3 "$UNPACK_BOOT" --boot_img "$OUT_DIR/recovery.img" --out "$TEMP_UNPACK_REC" >/dev/null
if (zcat "$TEMP_UNPACK_REC/ramdisk" | cpio -t | grep "recovery.fstab" >/dev/null 2>&1); then
    log_ok "recovery.img ramdisk contains verified recovery.fstab"
else
    log_err "recovery.img ramdisk lacks recovery.fstab!"
    ERRORS=$((ERRORS + 1))
fi
rm -rf "$TEMP_UNPACK_REC"

# 6. Tarball Structure & Content Inspection
log_info "6. Inspecting device adaptation archive (device_akita_row_call.tar.xz)..."
TAR_CONTENTS=$(tar -tf "$OUT_DIR/device_akita_row_call.tar.xz")

check_tar_entry() {
    local entry="$1"
    if echo "$TAR_CONTENTS" | grep -q "$entry"; then
        log_ok "Archive contains: $entry"
    else
        log_err "Archive missing expected entry: $entry"
        ERRORS=$((ERRORS + 1))
    fi
}

check_tar_entry "partitions/boot.img"
check_tar_entry "partitions/recovery.img"
check_tar_entry "system/opt/halium-overlay/usr/lib/udev/rules.d/70-akita.rules"
check_tar_entry "system/opt/halium-overlay/etc/gbinder.conf"
check_tar_entry "system/opt/halium-overlay/etc/pulse/arm_droid_card_custom.pa"
check_tar_entry "system/opt/halium-overlay/etc/init/keystore.rc"
check_tar_entry "system/opt/halium-overlay/etc/init/wait_for_keymaster.rc"

# 7. Privacy & Git Hygiene Check
log_info "7. Ensuring no sensitive partition dumps or private data leaked into release..."
if echo "$TAR_CONTENTS" | grep -E "nvram|nvdata|proinfo|protect|seccfg"; then
    log_err "LEAK DETECTED: Private partition dump found inside adaptation archive!"
    ERRORS=$((ERRORS + 1))
else
    log_ok "Zero private or sensitive partition dumps present in archive"
fi

echo -e "\n${BOLD}=== Installation Package Validation Summary ===${RESET}"
if [ "$ERRORS" -eq 0 ]; then
    log_ok "All installation package validation tests PASSED!"
    exit 0
else
    log_err "$ERRORS validation checks failed!"
    exit 1
fi
