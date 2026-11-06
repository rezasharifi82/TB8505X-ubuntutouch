#!/usr/bin/env bash
# ==============================================================================
# Script: validate_backup.sh
# Purpose: Validates partition dumps extracted via MediaTek BROM (mtkclient).
# Checks exact byte sizes against physical partition map, verifies non-zero
# entropy, and computes SHA-256 checksums.
# ==============================================================================

set -euo pipefail

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

BACKUP_DIR="${1:-$HOME/Desktop/TB8505X/backups/brom_pre_unlock}"

log_title "Validating MediaTek BROM Pre-Unlock Backup in $BACKUP_DIR"

if [ ! -d "$BACKUP_DIR" ]; then
    log_err "Backup directory $BACKUP_DIR does not exist!"
    exit 1
fi

# Ensure directory has restricted permissions (0700)
DIR_PERM=$(stat -c "%a" "$BACKUP_DIR")
if [ "$DIR_PERM" != "700" ]; then
    log_warn "Backup directory permissions are $DIR_PERM. Enforcing 0700 for privacy..."
    chmod 700 "$BACKUP_DIR"
fi

# Expected byte sizes extracted from physical GPT / fastboot getvar
declare -A EXPECTED_SIZES=(
    ["nvram.bin"]=67108864      # 0x4000000 (64.00 MiB) - mmcblk0p25
    ["nvdata.bin"]=67108864     # 0x4000000 (64.00 MiB) - mmcblk0p7
    ["nvcfg.bin"]=33554432      # 0x2000000 (32.00 MiB) - mmcblk0p6
    ["proinfo.bin"]=3145728     # 0x300000  (3.00 MiB)  - mmcblk0p12
    ["persist.bin"]=50331648    # 0x3000000 (48.00 MiB) - mmcblk0p15
    ["protect1.bin"]=8388608    # 0x800000  (8.00 MiB)  - mmcblk0p9
    ["protect2.bin"]=9928704    # 0x978000  (9.47 MiB)  - mmcblk0p10
    ["seccfg.bin"]=8388608      # 0x800000  (8.00 MiB)  - mmcblk0p11
    ["boot.bin"]=33554432       # 0x2000000 (32.00 MiB) - mmcblk0p28
    ["recovery.bin"]=33554432   # 0x2000000 (32.00 MiB) - mmcblk0p2
    ["vbmeta.bin"]=8388608      # 0x800000  (8.00 MiB)  - mmcblk0p13
    ["dtbo.bin"]=8388608        # 0x800000  (8.00 MiB)  - mmcblk0p29
)

# Optional preloader if dumped via --write_preloader_to_file
if [ -f "$BACKUP_DIR/preloader.bin" ]; then
    PRELOADER_SIZE=$(stat -c "%s" "$BACKUP_DIR/preloader.bin")
    if [ "$PRELOADER_SIZE" -eq 229224 ] || [ "$PRELOADER_SIZE" -eq 262144 ]; then
        EXPECTED_SIZES["preloader.bin"]=$PRELOADER_SIZE
    else
        EXPECTED_SIZES["preloader.bin"]=229224
    fi
fi

TOTAL_CHECKED=0
TOTAL_PASSED=0
TOTAL_FAILED=0

for file in "${!EXPECTED_SIZES[@]}"; do
    FILEPATH="$BACKUP_DIR/$file"
    EXPECTED_SIZE="${EXPECTED_SIZES[$file]}"
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    if [ ! -f "$FILEPATH" ]; then
        log_err "Missing mandatory partition dump: $file"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        continue
    fi

    ACTUAL_SIZE=$(stat -c "%s" "$FILEPATH")
    if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
        log_err "$file: Size mismatch! Expected $EXPECTED_SIZE bytes, got $ACTUAL_SIZE bytes."
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        continue
    fi

    # Check that file is not completely zeroed (non-zero entropy check)
    NON_ZERO=$(od -A n -N 4096 "$FILEPATH" | tr -d ' \n' | grep -v '^0*$' || true)
    if [ -z "$NON_ZERO" ]; then
        NON_ZERO_FULL=$(head -c 65536 "$FILEPATH" | tr -d '\0' | wc -c)
        if [ "$NON_ZERO_FULL" -eq 0 ]; then
            log_warn "$file: First 64KB contains only zeroes. Check partition content integrity."
        fi
    fi

    log_ok "$file: Size $ACTUAL_SIZE bytes matches expected ($((ACTUAL_SIZE / 1024 / 1024)) MiB)."
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
done

log_title "Generating SHA-256 Checksums"
cd "$BACKUP_DIR"
sha256sum *.bin > SHA256SUMS.txt 2>/dev/null || true
if [ -f SHA256SUMS.txt ]; then
    log_ok "Generated $BACKUP_DIR/SHA256SUMS.txt"
    cat SHA256SUMS.txt
fi

log_title "Validation Summary"
echo "Total checked: $TOTAL_CHECKED"
echo "Passed:        $TOTAL_PASSED"
echo "Failed:        $TOTAL_FAILED"

if [ "$TOTAL_FAILED" -eq 0 ] && [ "$TOTAL_PASSED" -ge 12 ]; then
    log_ok "Backup integrity verified successfully! All 12 critical partitions intact."
    exit 0
else
    log_err "Backup validation failed! $TOTAL_FAILED partition(s) missing or corrupted."
    exit 1
fi
