#!/usr/bin/env bash
# ==============================================================================
# Script: assemble_images.sh
# Purpose: Assembles and verifies flashable partition images and adaptation archives
# Target: Lenovo Tab M8 HD LTE (TB-8505X)
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$HERE/out"
TMP_PARTITIONS="$HERE/workdir/tmp/partitions"

mkdir -p "$OUT_DIR"

echo "=== Assembling Flashable Images for Lenovo TB-8505X ==="

if [ -f "$TMP_PARTITIONS/boot.img" ]; then
    echo "Copying boot.img to $OUT_DIR..."
    cp "$TMP_PARTITIONS/boot.img" "$OUT_DIR/boot.img"
fi

if [ -f "$TMP_PARTITIONS/recovery.img" ]; then
    echo "Copying recovery.img to $OUT_DIR..."
    cp "$TMP_PARTITIONS/recovery.img" "$OUT_DIR/recovery.img"
fi

if [ -f "$OUT_DIR/boot.img" ] && [ -f "$OUT_DIR/recovery.img" ] && [ -f "$OUT_DIR/device_akita_row_call.tar.xz" ]; then
    echo "Recalculating release SHA-256 checksums..."
    cd "$OUT_DIR"
    sha256sum boot.img recovery.img device_akita_row_call.tar.xz Module.symvers > SHA256SUMS.txt
    echo "Manifest generated:"
    cat SHA256SUMS.txt
fi

echo "Assembly complete."
