#!/usr/bin/env bash
# ==============================================================================
# Script: backup_partitions.sh
# Purpose: Safe backup utility for Lenovo TB-8505X unique radio & calibration
#          partitions (nvram, nvdata, nvcfg, proinfo, persist, protect1/2, seccfg).
# Safety:  DEFAULTS TO DRY-RUN. Never writes to device partitions.
#          Stores dumps OUTSIDE of any Git repository.
# Usage:
#   ./backup_partitions.sh --dry-run
#   ./backup_partitions.sh --dump /path/to/backup_dir
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

CRITICAL_PARTITIONS=(
    "nvram"
    "nvdata"
    "nvcfg"
    "proinfo"
    "persist"
    "protect1"
    "protect2"
    "seccfg"
)

PRELOADER_BLOCKS=(
    "mmcblk0boot0"
    "mmcblk0boot1"
)

print_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run                 Simulate partition discovery and safety checks (default)"
    echo "  --dump <output_dir>       Execute partition extraction via ADB root into <output_dir>"
    echo "  --help                    Show this help message"
    echo ""
    echo "Safety Notice:"
    echo "  - Backups MUST be stored outside git-tracked directories."
    echo "  - Dumping requires root permissions (Magisk or su) on the tablet if booted in Android."
    echo "  - In BROM mode, mtkclient can dump partitions without root or bootloader unlocking."
}

MODE="dry-run"
OUT_DIR=""

if [ "$#" -eq 0 ]; then
    MODE="dry-run"
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --dump)
            if [ "$#" -lt 2 ]; then
                log_err "--dump requires an output directory argument."
                exit 1
            fi
            MODE="dump"
            OUT_DIR="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            log_err "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

log_title "Lenovo TB-8505X Partition Backup Utility (Mode: $MODE)"

# 1. Workspace Safety Check
if [ "$MODE" = "dump" ]; then
    OUT_DIR=$(realpath -m "$OUT_DIR")
    # Check if inside git repo
    if git -C "$OUT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || git -C "$(dirname "$OUT_DIR")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_err "SAFETY VIOLATION: Target directory '$OUT_DIR' appears to be inside a Git repository!"
        log_err "Private calibration, IMEI, and NVRAM data must NEVER be committed to Git."
        exit 1
    fi
    mkdir -p "$OUT_DIR"
    log_ok "Target directory verified safe outside Git: $OUT_DIR"
fi

# 2. Check Device Connection
if ! command -v adb >/dev/null 2>&1; then
    log_err "ADB is required but not installed."
    exit 1
fi

DEVS=$(adb devices | grep -v 'List of devices' | grep 'device' || true)
if [ -z "$DEVS" ]; then
    log_warn "No active ADB device detected."
    log_info "If device is in Fastboot mode or BROM, ADB commands cannot dump partitions."
    log_info "For pre-unlock BROM dump, use mtkclient on Linux:"
    log_info "  python3 mtk r nvram,nvdata,nvcfg,proinfo,persist,protect1,protect2,seccfg,boot,vbmeta /path/to/backup"
    if [ "$MODE" = "dump" ]; then
        exit 1
    fi
fi

# 3. Partition Verification
log_title "Critical Radio & Calibration Partitions:"
for part in "${CRITICAL_PARTITIONS[@]}"; do
    echo "  - $part (Contains IMEI, MAC addresses, calibration, radio config)"
done
for blk in "${PRELOADER_BLOCKS[@]}"; do
    echo "  - $blk (Contains MediaTek eMMC boot preloader)"
done

if [ "$MODE" = "dry-run" ]; then
    log_title "Dry-Run Simulation Complete"
    log_info "To execute a backup when ADB root is available, run:"
    log_info "  $0 --dump ~/Desktop/TB8505X/backups/$(date +%Y%m%d_%H%M%S)"
    exit 0
fi

# 4. Execute Dump via ADB (only when explicitly requested)
log_title "Executing Partition Dump via ADB Root"

# Test root access
if ! adb shell "su -c 'id'" 2>&1 | grep -q "uid=0"; then
    log_err "Device ADB shell does not have root ('su') access."
    log_err "Cannot read raw block partitions without root or BROM access."
    exit 1
fi

REMOTE_TMP="/data/local/tmp/tb_backup_tmp"
adb shell "mkdir -p $REMOTE_TMP"

log_info "Extracting partitions on tablet..."
BY_NAME=$(adb shell "ls -d /dev/block/platform/*/by-name 2>/dev/null | head -1" | tr -d '\r')

if [ -z "$BY_NAME" ]; then
    log_err "Could not resolve /dev/block/platform/*/by-name path."
    exit 1
fi

for part in "${CRITICAL_PARTITIONS[@]}"; do
    log_info "Dumping $part..."
    adb shell "su -c 'if [ -e $BY_NAME/$part ]; then dd if=$BY_NAME/$part of=$REMOTE_TMP/${part}.img bs=1M 2>/dev/null; fi'"
done

for blk in "${PRELOADER_BLOCKS[@]}"; do
    log_info "Dumping $blk..."
    adb shell "su -c 'if [ -e /dev/block/$blk ]; then dd if=/dev/block/$blk of=$REMOTE_TMP/${blk}.img bs=1M 2>/dev/null; fi'"
done

log_info "Generating SHA256 checksums on device..."
adb shell "su -c 'cd $REMOTE_TMP && sha256sum *.img > SHA256SUMS.txt'"

log_info "Pulling backups to host: $OUT_DIR"
adb pull "$REMOTE_TMP/." "$OUT_DIR/"

log_info "Cleaning up temporary files on tablet..."
adb shell "su -c 'rm -rf $REMOTE_TMP'"

log_title "Verifying Pulled Checksums on Host"
cd "$OUT_DIR"
if [ -f "SHA256SUMS.txt" ]; then
    sha256sum -c SHA256SUMS.txt
    log_ok "All backup checksums verified successfully!"
else
    log_err "SHA256SUMS.txt not found in backup output!"
    exit 1
fi

log_title "Backup Completed Successfully in: $OUT_DIR"
exit 0
