#!/usr/bin/env bash
# ==============================================================================
# Script: prepare_ubuntu_touch_24_04_ota.sh
# Purpose: Downloads official UBports Ubuntu 24.04 (Noble) rootfs and Halium 10 GSI,
#          injects adaptation overrides, and builds the recovery OTA package.
# Target: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

OUT_OTA="$HERE/out/ota_24_04"
DEVICE_TARBALL="$HERE/out/device_akita_row_call_usrmerge.tar.xz"

if [ ! -f "$DEVICE_TARBALL" ]; then
    echo "[!] Target tarball $DEVICE_TARBALL not found!"
    echo "[*] Falling back to standard device tarball..."
    DEVICE_TARBALL="$HERE/out/device_akita_row_call.tar.xz"
fi

if [ ! -f "$DEVICE_TARBALL" ]; then
    echo "[ERROR] No device adaptation tarball found in $HERE/out/!"
    exit 1
fi

echo "================================================================================"
echo " Preparing Ubuntu Touch 24.04 (Noble) OTA Installation Bundle"
echo " Target Device: Lenovo Tab M8 HD LTE (akita_row_call / TB-8505X)"
echo " Device Tarball: $(basename "$DEVICE_TARBALL")"
echo " Output Dir: $OUT_OTA"
echo "================================================================================"

mkdir -p "$OUT_OTA"

# Ensure fakeroot is available
if ! command -v fakeroot &>/dev/null; then
    echo "[ERROR] 'fakeroot' is required. Install via: sudo apt-get install -y fakeroot"
    exit 1
fi

# Execute UBports official OTA generator
echo "[+] Running UBports prepare-fake-ota.sh..."
"$HERE/build/prepare-fake-ota.sh" "$DEVICE_TARBALL" "$OUT_OTA"

echo "[+] Generating SHA-256 manifest for OTA bundle..."
cd "$OUT_OTA"
find . -maxdepth 1 -type f ! -name "SHA256SUMS.txt" -printf "%f\n" | sort | xargs sha256sum > SHA256SUMS.txt
echo "[OK] Generated $OUT_OTA/SHA256SUMS.txt:"
cat SHA256SUMS.txt

echo "================================================================================"
echo " Ubuntu Touch 24.04 OTA Bundle Ready!"
echo " Directory: $OUT_OTA"
echo "================================================================================"
